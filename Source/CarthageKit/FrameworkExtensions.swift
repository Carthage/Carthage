//
//  FrameworkExtensions.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-31.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Argo
import Foundation
import Result
import ReactiveCocoa

extension String {
	/// Returns a producer that will enumerate each line of the receiver, then
	/// complete.
	internal var linesProducer: SignalProducer<String, NoError> {
		return SignalProducer { observer, disposable in
			(self as NSString).enumerateLinesUsingBlock { (line, stop) in
				observer.sendNext(line)

				if disposable.disposed {
					stop.memory = true
				}
			}

			observer.sendCompleted()
		}
	}
}

/// Merges `rhs` into `lhs` and returns the result.
internal func combineDictionaries<K, V>(lhs: [K: V], rhs: [K: V]) -> [K: V] {
	var result = lhs
	for (key, value) in rhs {
		result.updateValue(value, forKey: key)
	}

	return result
}

extension SignalType {
	/// Sends each value that occurs on `signal` combined with each value that
	/// occurs on `otherSignal` (repeats included).
	internal func permuteWith<U>(otherSignal: Signal<U, Error>) -> Signal<(Value, U), Error> {
		return Signal { observer in
			let lock = NSLock()
			lock.name = "org.carthage.CarthageKit.permuteWith"

			var signalValues: [Value] = []
			var signalCompleted = false
			var otherValues: [U] = []
			var otherCompleted = false

			let compositeDisposable = CompositeDisposable()

			compositeDisposable += self.observe { event in
				switch event {
				case let .Next(value):
					lock.lock()

					signalValues.append(value)
					for otherValue in otherValues {
						observer.sendNext((value, otherValue))
					}

					lock.unlock()

				case let .Failed(error):
					observer.sendFailed(error)

				case .Completed:
					lock.lock()

					signalCompleted = true
					if otherCompleted {
						observer.sendCompleted()
					}

					lock.unlock()

				case .Interrupted:
					observer.sendInterrupted()
				}
			}

			compositeDisposable += otherSignal.observe { event in
				switch event {
				case let .Next(value):
					lock.lock()

					otherValues.append(value)
					for signalValue in signalValues {
						observer.sendNext((signalValue, value))
					}

					lock.unlock()

				case let .Failed(error):
					observer.sendFailed(error)

				case .Completed:
					lock.lock()

					otherCompleted = true
					if signalCompleted {
						observer.sendCompleted()
					}

					lock.unlock()

				case .Interrupted:
					observer.sendInterrupted()
				}
			}

			return compositeDisposable
		}
	}
}

extension SignalProducerType {
	/// Sends each value that occurs on `producer` combined with each value that
	/// occurs on `otherProducer` (repeats included).
	internal func permuteWith<U>(otherProducer: SignalProducer<U, Error>) -> SignalProducer<(Value, U), Error> {
		return lift(Signal.permuteWith)(otherProducer)
	}
}

extension SignalType where Value: EventType, Value.Error == Error {
	/// Dematerializes the signal, like dematerialize(), but only yields inner
	/// Error events if no values were sent.
	internal func dematerializeErrorsIfEmpty() -> Signal<Value.Value, Error> {
		return Signal { observer in
			var receivedValue = false
			var receivedError: Error? = nil

			return self.observe { event in
				switch event {
				case let .Next(innerEvent):
					switch innerEvent.event {
					case let .Next(value):
						receivedValue = true
						observer.sendNext(value)

					case let .Failed(error):
						receivedError = error

					case .Completed:
						observer.sendCompleted()

					case .Interrupted:
						observer.sendInterrupted()
					}

				case let .Failed(error):
					observer.sendFailed(error)

				case .Completed:
					if let receivedError = receivedError where !receivedValue {
						observer.sendFailed(receivedError)
					}

					observer.sendCompleted()

				case .Interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}
}

extension SignalProducerType where Value: EventType, Value.Error == Error {
	/// Dematerializes the producer, like dematerialize(), but only yields inner
	/// Error events if no values were sent.
	internal func dematerializeErrorsIfEmpty() -> SignalProducer<Value.Value, Error> {
		return lift { $0.dematerializeErrorsIfEmpty() }
	}
}

/// Sends all permutations of the values from the input producers, as they arrive.
///
/// If no input producers are given, sends a single empty array then completes.
internal func permutations<T, E>(producers: [SignalProducer<T, E>]) -> SignalProducer<[T], E> {
	var combined: SignalProducer<[T], E> = SignalProducer(value: [])

	for producer in producers {
		combined = combined
			.permuteWith(producer)
			.map { array, value in
				var array = array
				array.append(value)
				return array
			}
	}

	return combined
}

extension NSScanner {
	/// Returns the current line being scanned.
	internal var currentLine: NSString {
		// Force Foundation types, so we don't have to use Swift's annoying
		// string indexing.
		let nsString: NSString = string
		let scanRange: NSRange = NSMakeRange(scanLocation, 0)
		let lineRange: NSRange = nsString.lineRangeForRange(scanRange)

		return nsString.substringWithRange(lineRange)
	}
}

private let defaultSessionError = NSError(domain: "org.carthage.CarthageKit.carthage_downloadWithRequest", code: 1, userInfo: nil)

extension NSURLSession {
	/// Returns a producer that will download a file using the given request. The
	/// file will be deleted after the producer terminates.
	internal func carthage_downloadWithRequest(request: NSURLRequest) -> SignalProducer<(NSURL, NSURLResponse), NSError> {
		return SignalProducer { observer, disposable in
			let serialDisposable = SerialDisposable()
			let handle = disposable.addDisposable(serialDisposable)

			let task = self.downloadTaskWithRequest(request) { (URL, response, error) in
				// Avoid invoking cancel(), or the download may be deleted.
				handle.remove()

				if let URL = URL, response = response {
					observer.sendNext((URL, response))
					observer.sendCompleted()
				} else {
					observer.sendFailed(error ?? defaultSessionError)
				}
			}

			serialDisposable.innerDisposable = ActionDisposable {
				task.cancel()
			}

			task.resume()
		}
	}
}

extension NSURL {
	/// The type identifier of the receiver, or an error if it was unable to be
	/// determined.
	internal var typeIdentifier: Result<String, CarthageError> {
		var error: NSError?

		do {
			var typeIdentifier: AnyObject?
			try getResourceValue(&typeIdentifier, forKey: NSURLTypeIdentifierKey)

			if let identifier = typeIdentifier as? String {
				return .Success(identifier)
			}
		} catch let err as NSError {
			error = err
		}

		return .Failure(.ReadFailed(self, error))
	}

	public func hasSubdirectory(possibleSubdirectory: NSURL) -> Bool {
		if scheme == possibleSubdirectory.scheme, let path = self.pathComponents, otherPath = possibleSubdirectory.pathComponents where path.count <= otherPath.count {
			return Array(otherPath[path.indices]) == path
		}
		return false
	}
}

extension NSURL: Decodable {
	public class func decode(json: JSON) -> Decoded<NSURL> {
		return String.decode(json).flatMap { URLString in
			return .fromOptional(self.init(string: URLString))
		}
	}
}

extension NSFileManager {
	/// Creates a directory enumerator at the given URL. Sends each URL
	/// enumerated, along with the enumerator itself (so it can be introspected
	/// and modified as enumeration progresses).
	public func carthage_enumeratorAtURL(URL: NSURL, includingPropertiesForKeys keys: [String], options: NSDirectoryEnumerationOptions, catchErrors: Bool = false) -> SignalProducer<(NSDirectoryEnumerator, NSURL), CarthageError> {
		return SignalProducer { observer, disposable in
			let enumerator = self.enumeratorAtURL(URL, includingPropertiesForKeys: keys, options: options) { (URL, error) in
				if catchErrors {
					return true
				} else {
					observer.sendFailed(CarthageError.ReadFailed(URL, error))
					return false
				}
			}!

			while !disposable.disposed {
				if let URL = enumerator.nextObject() as? NSURL {
					let value = (enumerator, URL)
					observer.sendNext(value)
				} else {
					break
				}
			}

			observer.sendCompleted()
		}
	}
}

/// Creates a counted set from a sequence. The counted set is represented as a
/// dictionary where the keys are elements from the sequence and values count
/// how many times elements are present in the sequence.
internal func buildCountedSet<S: SequenceType>(sequence: S) -> [S.Generator.Element: Int] {
	return sequence.reduce([:]) { set, elem in
		var set = set
		if let count = set[elem] {
			set[elem] = count + 1
		}
		else {
			set[elem] = 1
		}
		return set
	}
}
