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
				sendNext(observer, line)

				if disposable.disposed {
					stop.memory = true
				}
			}

			sendCompleted(observer)
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

/// Sends each value that occurs on `signal` combined with each value that
/// occurs on `otherSignal` (repeats included).
internal func permuteWith<T, U, E>(otherSignal: Signal<U, E>) -> Signal<T, E> -> Signal<(T, U), E> {
	return { signal in
		return Signal { observer in
			let lock = NSLock()
			lock.name = "org.carthage.CarthageKit.permuteWith"

			var signalValues: [T] = []
			var signalCompleted = false
			var otherValues: [U] = []
			var otherCompleted = false

			let compositeDisposable = CompositeDisposable()

			compositeDisposable += signal.observe(next: { value in
				lock.lock()

				signalValues.append(value)
				for otherValue in otherValues {
					sendNext(observer, (value, otherValue))
				}

				lock.unlock()
			}, error: { error in
				sendError(observer, error)
			}, completed: {
				lock.lock()

				signalCompleted = true
				if otherCompleted {
					sendCompleted(observer)
				}

				lock.unlock()
			}, interrupted: {
				sendInterrupted(observer)
			})

			compositeDisposable += otherSignal.observe(next: { value in
				lock.lock()

				otherValues.append(value)
				for signalValue in signalValues {
					sendNext(observer, (signalValue, value))
				}

				lock.unlock()
			}, error: { error in
				sendError(observer, error)
			}, completed: {
				lock.lock()

				otherCompleted = true
				if signalCompleted {
					sendCompleted(observer)
				}

				lock.unlock()
			}, interrupted: {
				sendInterrupted(observer)
			})

			return compositeDisposable
		}
	}
}

/// Sends each value that occurs on `producer` combined with each value that
/// occurs on `otherProducer` (repeats included).
internal func permuteWith<T, U, E>(otherProducer: SignalProducer<U, E>)(producer: SignalProducer<T, E>) -> SignalProducer<(T, U), E> {
	return producer.lift(permuteWith)(otherProducer)
}

/// Dematerializes the signal, like dematerialize(), but only yields inner Error
/// events if no values were sent.
internal func dematerializeErrorsIfEmpty<T, E>(signal: Signal<Event<T, E>, E>) -> Signal<T, E> {
	return Signal { observer in
		var receivedValue = false
		var receivedError: E? = nil

		return signal.observe(next: { event in
			switch event {
			case let .Next(value):
				receivedValue = true
				sendNext(observer, value.value)

			case let .Error(error):
				receivedError = error.value

			case .Completed:
				sendCompleted(observer)

			case .Interrupted:
				sendInterrupted(observer)
			}
		}, error: { error in
			sendError(observer, error)
		}, completed: {
			if !receivedValue {
				if let receivedError = receivedError {
					sendError(observer, receivedError)
				}
			}

			sendCompleted(observer)
		}, interrupted: {
			sendInterrupted(observer)
		})
	}
}

/// Sends all permutations of the values from the input producers, as they arrive.
///
/// If no input producers are given, sends a single empty array then completes.
internal func permutations<T, E>(producers: [SignalProducer<T, E>]) -> SignalProducer<[T], E> {
	var combined: SignalProducer<[T], E> = SignalProducer(value: [])

	for producer in producers {
		combined = combined
			|> permuteWith(producer)
			|> map { (var array, value) in
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
					sendNext(observer, (URL, response))
					sendCompleted(observer)
				} else {
					sendError(observer, error)
				}
			}

			serialDisposable.innerDisposable = ActionDisposable {
				task.cancel()
			}

			task.resume()
		}
	}
}

extension NSURL: Decodable {
	public class func decode(json: JSON) -> Decoded<NSURL> {
		return String.decode(json).flatMap { URLString in
			return .fromOptional(self(string: URLString))
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
					sendError(observer, CarthageError.ReadFailed(URL, error))
					return false
				}
			}!

			while !disposable.disposed {
				if let URL = enumerator.nextObject() as? NSURL {
					let value = (enumerator, URL)
					sendNext(observer, value)
				} else {
					break
				}
			}

			sendCompleted(observer)
		}
	}
}

/// Creates a counted set from a sequence. The counted set is represented as a
/// dictionary where the keys are elements from the sequence and values count
/// how many times elements are present in the sequence.
internal func buildCountedSet<S: SequenceType>(sequence: S) -> [S.Generator.Element: Int] {
	return reduce(sequence, [:]) { (var set, elem) in
		if let count = set[elem] {
			set[elem] = count + 1
		}
		else {
			set[elem] = 1
		}
		return set
	}
}
