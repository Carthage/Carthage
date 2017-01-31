//
//  ProducerQueue.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2015-05-23.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import ReactiveSwift

/// Serializes the execution of SignalProducers, like flatten(.concat), but
/// without all needing to be enqueued in the same context.
///
/// This allows you to manually enqueue producers from any code that has access
/// to the queue object, instead of being required to funnel all producers
/// through a single producer-of-producers.
internal final class ProducerQueue {
	private let queue: DispatchQueue

	/// Initializes a queue with the given debug name.
	init(name: String) {
		queue = DispatchQueue(label: name)
	}

	/// Creates a SignalProducer that will enqueue the given producer when
	/// started, wait until the queue is empty to begin work, and block other
	/// work while executing.
	func enqueue<T, Error>(_ producer: SignalProducer<T, Error>) -> SignalProducer<T, Error> {
		return SignalProducer { observer, disposable in
			self.queue.async {
				if disposable.isDisposed {
					return
				}

				// Prevent further operations from starting until we're
				// done.
				self.queue.suspend()

				producer.startWithSignal { signal, signalDisposable in
					disposable.add(signalDisposable)

					signal.observe { event in
						observer.action(event)

						if event.isTerminating {
							self.queue.resume()
						}
					}
				}
			}
		}
	}
}

extension SignalProducerProtocol {
	/// Shorthand for enqueuing the given producer upon the given queue.
	internal func startOnQueue(_ queue: ProducerQueue) -> SignalProducer<Value, Error> {
		return queue.enqueue(self.producer)
	}
}
