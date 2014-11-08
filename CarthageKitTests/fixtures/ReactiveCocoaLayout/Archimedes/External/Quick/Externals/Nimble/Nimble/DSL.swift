import Foundation

// Begins an assertion on a given value.
// file: and line: can be omitted to default to the current line this function is called on.
public func expect<T>(expression: @autoclosure () -> T?, file: String = __FILE__, line: UInt = __LINE__) -> Expectation<T> {
    return Expectation(
        expression: Expression(
            expression: expression,
            location: SourceLocation(file: file, line: line)))
}

// Begins an assertion on a given value.
// file: and line: can be omitted to default to the current line this function is called on.
public func expect<T>(file: String = __FILE__, line: UInt = __LINE__, expression: () -> T?) -> Expectation<T> {
    return Expectation(
        expression: Expression(
            expression: expression,
            location: SourceLocation(file: file, line: line)))
}

// Begins an assertion on a given value.
// file: and line: can be omitted to default to the current line this function is called on.
public func waitUntil(#timeout: NSTimeInterval, action: (() -> Void) -> Void, file: String = __FILE__, line: UInt = __LINE__) -> Void {
    var completed = false
    dispatch_async(dispatch_get_main_queue()) {
        action() { completed = true }
    }
    let passed = _pollBlock(pollInterval: 0.01, timeoutInterval: timeout) {
        return completed
    }
    if !passed {
        let pluralize = (timeout == 1 ? "" : "s")
        fail("Waited more than \(timeout) second\(pluralize)", file: file, line: line)
    }
}

// Begins an assertion on a given value.
// file: and line: can be omitted to default to the current line this function is called on.
public func waitUntil(action: (() -> Void) -> Void, file: String = __FILE__, line: UInt = __LINE__) -> Void {
    waitUntil(timeout: 1, action, file: file, line: line)
}

public func fail(message: String, #location: SourceLocation) {
    CurrentAssertionHandler.assert(false, message: message, location: location)
}

public func fail(message: String, file: String = __FILE__, line: UInt = __LINE__) {
    fail(message, location: SourceLocation(file: file, line: line))
}

public func fail(file: String = __FILE__, line: UInt = __LINE__) {
    fail("fail() always fails")
}