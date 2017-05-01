//
//  ProducerQueue.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2015-05-23.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import ReactiveSwift

/// Serializes or parallelizes (up to a limit) the execution of many 
/// SignalProducers, like flatten(.concat) or flatten(.merge), but without all
/// needing to be enqueued in the same context.
///
/// This allows you to manually enqueue producers from any code that has access
/// to the queue object, instead of being required to funnel all producers
/// through a single producer-of-producers.
internal final class ProducerQueue {
	private let concurrentQueue: DispatchQueue
	private let serialQueue: DispatchQueue
	private let semaphore: DispatchSemaphore

	/// Initializes a queue with the given debug name and a limit indicating the
	/// maximum number of producers that can be executing concurrently.
	init(name: String, limit: Int = 1) {
		concurrentQueue = DispatchQueue(label: name.appending(".concurrent"), qos: .userInitiated, attributes: .concurrent)
		serialQueue = DispatchQueue(label: name.appending(".serial"), qos: .default)
		semaphore = DispatchSemaphore(value: limit)
	}

	/// Creates a SignalProducer that will enqueue the given producer when 
	/// started.
	func enqueue<T, Error>(_ producer: SignalProducer<T, Error>) -> SignalProducer<T, Error> {
		return SignalProducer { observer, disposable in
			self.serialQueue.async {
				if disposable.isDisposed {
					return
				}

				// Prevent more than the limit of operations from occurring
				// concurrently.
				//
				// Block the serial queue to prevent creating a new thread on 
				// the concurrent queue just to immediately block it.
				self.semaphore.wait()

				self.concurrentQueue.async {
					if disposable.isDisposed {
						self.semaphore.signal()
						return
					}

					producer.startWithSignal { signal, signalDisposable in
						disposable.add(signalDisposable)

						signal.observe { event in
							observer.action(event)

							if event.isTerminating {
								self.semaphore.signal()
							}
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
