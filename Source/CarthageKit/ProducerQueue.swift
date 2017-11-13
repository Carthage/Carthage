import Dispatch
import Foundation
import ReactiveSwift

/// Manages the execution of SignalProducers, like the flatten(...) operator,
/// but without all needing to be enqueued in the same context.
///
/// This allows you to manually enqueue producers from any code that has access
/// to the queue object, instead of being required to funnel all producers
/// through a single producer-of-producers.
internal protocol ProducerQueue {
	/// Creates a SignalProducer that will enqueue the given producer when
	/// started, wait until the queue is has room to begin work, and block other
	/// work while executing.
	func enqueue<T, Error>(_ producer: SignalProducer<T, Error>) -> SignalProducer<T, Error>
}

extension SignalProducer {
	/// Shorthand for enqueuing the given producer upon the given queue.
	internal func startOnQueue(_ queue: ProducerQueue) -> SignalProducer<Value, Error> {
		return queue.enqueue(self.producer)
	}
}

/// Serializes the execution of SignalProducers, like flatten(.concat), but
/// without all needing to be enqueued in the same context.
internal final class SerialProducerQueue: ProducerQueue {
	private let queue: DispatchQueue

	/// Initializes a queue with the given debug name.
	init(name: String) {
		queue = DispatchQueue(label: name)
	}

	/// Creates a SignalProducer that will enqueue the given producer when
	/// started, wait until the queue is empty to begin work, and block other
	/// work while executing.
	func enqueue<T, Error>(_ producer: SignalProducer<T, Error>) -> SignalProducer<T, Error> {
		return SignalProducer { observer, lifetime in
			self.queue.async {
				if lifetime.hasEnded {
					return
				}

				// Prevent further operations from starting until we're
				// done.
				self.queue.suspend()

				producer.startWithSignal { signal, signalDisposable in
					lifetime += signalDisposable

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

/// Parallelizes (up to a limit) the execution of many SignalProducers, like
/// flatten(.merge), but without all needing to be enqueued in the same context.
internal final class ConcurrentProducerQueue: ProducerQueue {
	private let operationQueue: OperationQueue

	/// Initializes a queue with the given debug name and a limit indicating the
	/// maximum number of producers that can be executing concurrently.
	init(name: String, limit: Int = 1) {
		operationQueue = OperationQueue()
		operationQueue.name = name
		operationQueue.maxConcurrentOperationCount = limit
	}

	/// Creates a SignalProducer that will enqueue the given producer when 
	/// started.
	func enqueue<T, Error>(_ producer: SignalProducer<T, Error>) -> SignalProducer<T, Error> {
		return SignalProducer { observer, lifetime in
			let operation = Operation { operation in
				if lifetime.hasEnded {
					operation._isFinished = true
					return
				}

				producer.startWithSignal { signal, signalDisposable in
					lifetime += signalDisposable

					signal.observe { event in
						observer.action(event)

						if event.isTerminating {
							operation._isFinished = true
						}
					}
				}
			}

			self.operationQueue.addOperation(operation)
		}
	}

	/// An block operation that can only be finished by setting its _isFinished
	/// property to true.
	fileprivate final class Operation: BlockOperation {
		override var isFinished: Bool {
			return _isFinished && super.isFinished
		}

		var _isFinished: Bool = false {
			willSet { willChangeValue(forKey: "isFinished") }
			didSet { didChangeValue(forKey: "isFinished") }
		}

		init(_ block: @escaping (Operation) -> Void) {
			super.init()
			// This operation is retained by containing OperationQueue until it is
			// finished, so no need to capture self within the execution block.
			unowned let unownedSelf = self
			addExecutionBlock { block(unownedSelf) }
		}
	}
}
