//
//  FrameworkExtensions.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-31.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import Result
import ReactiveCocoa

extension String {
	/// Returns a producer that will enumerate each line of the receiver, then
	/// complete.
	internal var linesProducer: SignalProducer<String, NoError> {
		return SignalProducer { observer, disposable in
			(self as NSString).enumerateLinesUsingBlock { (line, stop) in
				observer.send(value: line)

				if disposable.isDisposed {
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

extension SignalProtocol {
	/// Sends each value that occurs on `signal` combined with each value that
	/// occurs on `otherSignal` (repeats included).
	private func permuteWith<U>(otherSignal: Signal<U, Error>) -> Signal<(Value, U), Error> {
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
						observer.send(value: (value, otherValue))
					}

					lock.unlock()

				case let .Failed(error):
					observer.send(error: error)

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
						observer.send(value: (signalValue, value))
					}

					lock.unlock()

				case let .Failed(error):
					observer.send(error: error)

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

extension SignalProducerProtocol {
	/// Sends each value that occurs on `producer` combined with each value that
	/// occurs on `otherProducer` (repeats included).
	private func permuteWith<U>(otherProducer: SignalProducer<U, Error>) -> SignalProducer<(Value, U), Error> {
		// This should be the implementation of this method:
		// return lift(Signal.permuteWith)(otherProducer)
		//
		// However, due to a Swift miscompilation (with `-O`) we need to inline `lift` here.
		// See https://github.com/ReactiveCocoa/ReactiveCocoa/issues/2751 for more details.
		//
		// This can be reverted once tests with -O don't crash.

		return SignalProducer { observer, outerDisposable in
			self.startWithSignal { signal, disposable in
				outerDisposable.add(disposable)

				otherProducer.startWithSignal { otherSignal, otherDisposable in
					outerDisposable.add(otherDisposable)

					signal.permuteWith(otherSignal).observe(observer)
				}
			}
		}
	}
	
	/// Sends a boolean of whether the producer succeeded or failed.
	internal func succeeded() -> SignalProducer<Bool, NoError> {
		return self
			.then(.init(value: true))
			.flatMapError { _ in .init(value: false) }
	}
}

extension SignalProducerProtocol where Value: SignalProducerProtocol, Error == Value.Error {
	/// Sends all permutations of the values from the inner producers, as they arrive.
	///
	/// If no producers are received, sends a single empty array then completes.
	@warn_unused_result(message="Did you forget to call `start` on the producer?")
	internal func permute() -> SignalProducer<[Value.Value], Error> {
		return self
			.collect()
			.flatMap(.concat) { (producers: [Value]) -> SignalProducer<[Value.Value], Error> in
				var combined = SignalProducer<[Value.Value], Error>(value: [])

				for producer in producers {
					combined = combined
						.permuteWith(producer.producer)
						.map { array, value in
							var array = array
							array.append(value)
							return array
						}
				}

				return combined
			}
	}
}

extension SignalProtocol where Value: EventProtocol, Value.Error == Error {
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
						observer.send(value: value)

					case let .Failed(error):
						receivedError = error

					case .Completed:
						observer.sendCompleted()

					case .Interrupted:
						observer.sendInterrupted()
					}

				case let .Failed(error):
					observer.send(error: error)

				case .Completed:
					if let receivedError = receivedError where !receivedValue {
						observer.send(error: receivedError)
					}

					observer.sendCompleted()

				case .Interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}
}

extension SignalProducerProtocol where Value: EventProtocol, Value.Error == Error {
	/// Dematerializes the producer, like dematerialize(), but only yields inner
	/// Error events if no values were sent.
	internal func dematerializeErrorsIfEmpty() -> SignalProducer<Value.Value, Error> {
		return lift { $0.dematerializeErrorsIfEmpty() }
	}
}

extension Scanner {
	/// Returns the current line being scanned.
	internal var currentLine: NSString {
		// Force Foundation types, so we don't have to use Swift's annoying
		// string indexing.
		let nsString = string as NSString
		let scanRange: NSRange = NSMakeRange(scanLocation, 0)
		let lineRange: NSRange = nsString.lineRangeForRange(scanRange)

		return nsString.substringWithRange(lineRange)
	}
}

extension URL {
	/// The type identifier of the receiver, or an error if it was unable to be
	/// determined.
	internal var typeIdentifier: Result<String, CarthageError> {
		var error: NSError?

		do {
			let typeIdentifier = try resourceValues(forKeys: [ .typeIdentifierKey ]).typeIdentifier
			if let identifier = typeIdentifier {
				return .success(identifier)
			}
		} catch let err as NSError {
			error = err
		}

		return .failure(.readFailed(self, error))
	}

	public var carthage_absoluteString: String {
		return absoluteString!
	}

	public func hasSubdirectory(possibleSubdirectory: URL) -> Bool {
		let standardizedSelf = self.standardizedFileURL
		let standardizedOther = possibleSubdirectory.standardizedFileURL

		let path = standardizedSelf.carthage_pathComponents
		let otherPath = standardizedOther.carthage_pathComponents
		if scheme == standardizedOther.scheme && path.count <= otherPath.count {
			return Array(otherPath[path.indices]) == path
		}

		return false
	}
}

extension FileManager {
	/// Creates a directory enumerator at the given URL. Sends each URL
	/// enumerated, along with the enumerator itself (so it can be introspected
	/// and modified as enumeration progresses).
	public func carthage_enumerator(at url: URL, includingPropertiesForKeys keys: [String], options: NSDirectoryEnumerationOptions = [], catchErrors: Bool = false) -> SignalProducer<(NSDirectoryEnumerator, URL), CarthageError> {
		return SignalProducer { observer, disposable in
			let enumerator = self.enumerator(at: url, includingPropertiesForKeys: keys, options: options) { (url, error) in
				if catchErrors {
					return true
				} else {
					observer.send(error: CarthageError.readFailed(url, error))
					return false
				}
			}!

			while !disposable.isDisposed {
				if let url = enumerator.nextObject() as? URL {
					let value = (enumerator, url)
					observer.send(value: value)
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
