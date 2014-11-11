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
			let queue = dispatch_queue_create("org.reactivecocoa.ReactiveCocoa.ColdSignal.recombineWith", DISPATCH_QUEUE_SERIAL)
			var selfValues: [T] = []
			var selfCompleted = false
			var otherValues: [U] = []
			var otherCompleted = false

			let selfDisposable = self.start(next: { value in
				dispatch_sync(queue) {
					selfValues.append(value)

					for otherValue in otherValues {
						subscriber.put(.Next(Box((value, otherValue))))
					}
				}
			}, error: { error in
				subscriber.put(.Error(error))
			}, completed: {
				dispatch_sync(queue) {
					selfCompleted = true
					if otherCompleted {
						subscriber.put(.Completed)
					}
				}
			})

			subscriber.disposable.addDisposable(selfDisposable)

			let otherDisposable = signal.start(next: { value in
				dispatch_sync(queue) {
					otherValues.append(value)

					for selfValue in selfValues {
						subscriber.put(.Next(Box((selfValue, value))))
					}
				}
			}, error: { error in
				subscriber.put(.Error(error))
			}, completed: {
				dispatch_sync(queue) {
					otherCompleted = true
					if selfCompleted {
						subscriber.put(.Completed)
					}
				}
			})

			subscriber.disposable.addDisposable(otherDisposable)
		}
	}

	/// Dematerializes the signal, like dematerialize(), but only yields Error
	/// events if no values were sent.
	internal func dematerializeErrorsIfEmpty<U>(evidence: ColdSignal -> ColdSignal<Event<U>>) -> ColdSignal<U> {
		return ColdSignal<U> { subscriber in
			let queue = dispatch_queue_create("org.reactivecocoa.ReactiveCocoa.ColdSignal.dematerializeErrorsIfEmpty", DISPATCH_QUEUE_SERIAL)
			var receivedValue = false
			var receivedError: NSError? = nil

			evidence(self).start(next: { event in
				switch event {
				case let .Next(value):
					dispatch_sync(queue) {
						receivedValue = true
					}

					fallthrough

				case .Completed:
					subscriber.put(event)

				case let .Error(error):
					dispatch_sync(queue) {
						receivedError = error
					}
				}
			}, error: { error in
				subscriber.put(.Error(error))
			}, completed: {
				dispatch_sync(queue) {
					if !receivedValue {
						if let receivedError = receivedError {
							subscriber.put(.Error(receivedError))
						}
					}
				}

				subscriber.put(.Completed)
			})
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
