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
		return SignalProducer { observer, disposable in
			let operation = ManuallyFinishingOperation { operation in
				if disposable.isDisposed {
					operation._isFinished = true
					return
				}

				producer.startWithSignal { signal, signalDisposable in
					disposable.add(signalDisposable)

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
}

/// An block operation that can only be finished by setting its _isFinished
/// property to true.
fileprivate final class ManuallyFinishingOperation: BlockOperation {
	override var isFinished: Bool {
		return _isFinished && super.isFinished
	}

	var _isFinished: Bool = false {
		willSet { willChangeValue(forKey: "isFinished") }
		didSet { didChangeValue(forKey: "isFinished") }
	}

	init(_ block: @escaping (ManuallyFinishingOperation) -> Void) {
		super.init()
		addExecutionBlock { block(self) }
	}
}

extension SignalProducerProtocol {
	/// Shorthand for enqueuing the given producer upon the given queue.
	internal func startOnQueue(_ queue: ProducerQueue) -> SignalProducer<Value, Error> {
		return queue.enqueue(self.producer)
	}
}
