/*
This source file is part of the Swift.org open source project
Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception
See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Converts an asynchronous method having callback using Result enum to synchronous.
///
/// - Parameter body: The async method must be called inside this body and closure provided in the parameter
///                   should be passed to the async method's completion handler.
/// - Returns: The value wrapped by the async method's result.
/// - Throws: The error wrapped by the async method's result

import Result

public func await<T, ErrorType>(_ body: (@escaping (Result<T, ErrorType>) -> Void) -> Void) throws -> T {
	return try await(body).dematerialize()
}

public func await<T>(_ body: (@escaping (T) -> Void) -> Void) -> T {
	let condition = Condition()
	var result: T? = nil
	body { theResult in
		condition.whileLocked {
			result = theResult
			condition.signal()
		}
	}
	condition.whileLocked {
		while result == nil {
			condition.wait()
		}
	}
	return result!
}
