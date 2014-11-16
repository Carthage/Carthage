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
	public var linesSignal: ColdSignal<String> {
		return ColdSignal { subscriber in
			(self as NSString).enumerateLinesUsingBlock { (line, stop) in
				subscriber.put(.Next(Box(line as String)))

				if subscriber.disposable.disposed {
					stop.memory = true
				}
			}

			subscriber.put(.Completed)
		}
	}
}

/// Merges `rhs` into `lhs` and returns the result.
public func combineDictionaries<K, V>(lhs: [K: V], rhs: [K: V]) -> [K: V] {
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
		return ColdSignal<(T, U)> { subscriber in
			let scheduler = QueueScheduler()
			var selfValues: [T] = []
			var selfCompleted = false
			var otherValues: [U] = []
			var otherCompleted = false

			let schedulerDisposable = scheduler.schedule {
				let selfDisposable = self.deliverOn(scheduler).start(next: { value in
					selfValues.append(value)

					for otherValue in otherValues {
						subscriber.put(.Next(Box((value, otherValue))))
					}
				}, error: { error in
					subscriber.put(.Error(error))
				}, completed: {
					selfCompleted = true
					if otherCompleted {
						subscriber.put(.Completed)
					}
				})

				subscriber.disposable.addDisposable(selfDisposable)

				if subscriber.disposable.disposed {
					return
				}

				let otherDisposable = signal.deliverOn(scheduler).start(next: { value in
					otherValues.append(value)

					for selfValue in selfValues {
						subscriber.put(.Next(Box((selfValue, value))))
					}
				}, error: { error in
					subscriber.put(.Error(error))
				}, completed: {
					otherCompleted = true
					if selfCompleted {
						subscriber.put(.Completed)
					}
				})

				subscriber.disposable.addDisposable(otherDisposable)
			}

			subscriber.disposable.addDisposable(schedulerDisposable)
		}
	}

	/// Dematerializes the signal, like dematerialize(), but only yields Error
	/// events if no values were sent.
	internal func dematerializeErrorsIfEmpty<U>(evidence: ColdSignal -> ColdSignal<Event<U>>) -> ColdSignal<U> {
		return ColdSignal<U> { subscriber in
			let scheduler = QueueScheduler()
			var receivedValue = false
			var receivedError: NSError? = nil

			let schedulerDisposable = scheduler.schedule {
				let selfDisposable = evidence(self).deliverOn(scheduler).start(next: { event in
					switch event {
					case let .Next(value):
						receivedValue = true
						fallthrough

					case .Completed:
						subscriber.put(event)

					case let .Error(error):
						receivedError = error
					}
				}, error: { error in
					subscriber.put(.Error(error))
				}, completed: {
					if !receivedValue {
						if let receivedError = receivedError {
							subscriber.put(.Error(receivedError))
						}
					}

					subscriber.put(.Completed)
				})
				
				subscriber.disposable.addDisposable(selfDisposable)
			}

			subscriber.disposable.addDisposable(schedulerDisposable)
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
