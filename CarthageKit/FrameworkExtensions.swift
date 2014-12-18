//
//  FrameworkExtensions.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-31.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa

extension String {
	/// Returns a signal that will enumerate each line of the receiver, then
	/// complete.
	internal var linesSignal: ColdSignal<String> {
		return ColdSignal { (sink, disposable) in
			(self as NSString).enumerateLinesUsingBlock { (line, stop) in
				sink.put(.Next(Box(line as String)))

				if disposable.disposed {
					stop.memory = true
				}
			}

			sink.put(.Completed)
		}
	}
}

extension Array {
	/// Returns a signal that will enumerate each element of the receiver, then
	/// complete.
	internal var elementsSignal: ColdSignal<T> {
		return ColdSignal { (sink, disposable) in
			for element in self {
				sink.put(.Next(Box(element)))
			}

			sink.put(.Completed)
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

extension ColdSignal {
	/// Sends each value that occurs on the receiver combined with each value
	/// that occurs on the given signal (repeats included).
	internal func permuteWith<U>(signal: ColdSignal<U>) -> ColdSignal<(T, U)> {
		return ColdSignal<(T, U)> { (sink, disposable) in
			var selfValues: [T] = []
			var selfCompleted = false
			var otherValues: [U] = []
			var otherCompleted = false

			self.startWithSink { selfDisposable in
				disposable.addDisposable(selfDisposable)

				return eventSink(next: { value in
					selfValues.append(value)

					for otherValue in otherValues {
						sink.put(.Next(Box((value, otherValue))))
					}
				}, error: { error in
					sink.put(.Error(error))
				}, completed: {
					selfCompleted = true
					if otherCompleted {
						sink.put(.Completed)
					}
				})
			}

			signal.startWithSink { signalDisposable in
				disposable.addDisposable(signalDisposable)

				return eventSink(next: { value in
					otherValues.append(value)

					for selfValue in selfValues {
						sink.put(.Next(Box((selfValue, value))))
					}
				}, error: { error in
					sink.put(.Error(error))
				}, completed: {
					otherCompleted = true
					if selfCompleted {
						sink.put(.Completed)
					}
				})
			}
		}
	}

	/// Dematerializes the signal, like dematerialize(), but only yields Error
	/// events if no values were sent.
	internal func dematerializeErrorsIfEmpty<U>(evidence: ColdSignal -> ColdSignal<Event<U>>) -> ColdSignal<U> {
		return ColdSignal<U> { (sink, disposable) in
			var receivedValue = false
			var receivedError: NSError? = nil

			evidence(self).startWithSink { selfDisposable in
				disposable.addDisposable(selfDisposable)

				return eventSink(next: { event in
					switch event {
					case let .Next(value):
						receivedValue = true
						fallthrough

					case .Completed:
						sink.put(event)

					case let .Error(error):
						receivedError = error
					}
				}, error: { error in
					sink.put(.Error(error))
				}, completed: {
					if !receivedValue {
						if let receivedError = receivedError {
							sink.put(.Error(receivedError))
						}
					}

					sink.put(.Completed)
				})
			}
		}
	}
}

/// Sends all permutations of the values from the input signals, as they arrive.
///
/// If no input signals are given, sends a single empty array then completes.
internal func permutations<T>(signals: [ColdSignal<T>]) -> ColdSignal<[T]> {
	var combined: ColdSignal<[T]> = .single([])

	for signal in signals {
		combined = combined.permuteWith(signal).map { (var array, value) in
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
