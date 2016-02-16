import Foundation

public protocol Printer {
	func println()
	func println(object: Any)
	func print(object: Any)
}

internal struct ThreadSafePrinter: Printer {
	private static let outputQueue = { () -> dispatch_queue_t in
		let queue = dispatch_queue_create("org.carthage.carthage.outputQueue", DISPATCH_QUEUE_SERIAL)
		dispatch_set_target_queue(queue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0))

		atexit_b {
			dispatch_barrier_sync(queue) {}
		}

		return queue
	}()

	init() {}

	func println() {
		dispatch_async(ThreadSafePrinter.outputQueue) {
			Swift.print()
		}
	}

	func println(object: Any) {
		dispatch_async(ThreadSafePrinter.outputQueue) {
			Swift.print(object)
		}
	}

	func print(object: Any) {
		dispatch_async(ThreadSafePrinter.outputQueue) {
			Swift.print(object, terminator: "")
		}
	}
}
