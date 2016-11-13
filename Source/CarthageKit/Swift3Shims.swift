import Foundation
import Result
import ReactiveCocoa
import ReactiveTask

#if swift(>=3)
#else
	// MARK: - Result

	internal extension Result {
		static func success(value: Value) -> Result<Value, Error> {
			return .Success(value)
		}

		static func failure(error: Error) -> Result<Value, Error> {
			return .Failure(error)
		}
	}

	// MARK: - ReactiveSwift

	internal extension Observer {
		func send(value value: Value) {
			sendNext(value)
		}

		func send(error error: Error) {
			sendFailed(error)
		}
	}

	// MARK: - ReactiveTask

	internal extension TaskEvent {
		static func success(value: T) -> TaskEvent<T> {
			return .Success(value)
		}
	}

	internal extension TaskError {
		static func posixError(code: Int32) -> TaskError {
			return .POSIXError(code)
		}
	}

	internal extension Task {
		func launch(standardInput standardInput: SignalProducer<NSData, NoError>? = nil) -> SignalProducer<TaskEvent<NSData>, TaskError> {
			return launchTask(self, standardInput: standardInput)
		}
	}
#endif
