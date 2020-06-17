import Foundation

public extension Result {
    /// Returns value for `.success`, `nil` for `failure`
    var value: Success? { try? get() }
    
    /// Returns erro value for `.failure`, `nil` for `success`
    var error: Failure? {
        switch self {
        case .success: return nil
        case .failure(let error): return error
        }
    }
    
    /// Returns a Result with a tuple of the receiver and `other` values if both
    /// are `Success`es, or re-wrapping the error of the earlier `Failure`.
    func fanout<U>(_ other: @autoclosure () -> Result<U, Error>) -> Result<(Value, U), Error> {
        return self.flatMap { left in other().map { right in (left, right) } }
    }
    
    /// Returns the result of applying `transform` to `Success`es’ values, or re-wrapping `Failure`’s errors.
    func flatMap<U>(_ transform: (Value) -> Result<U, Error>) -> Result<U, Error> {
        switch self {
        case let .success(value): return transform(value)
        case let .failure(error): return .failure(error)
        }
    }
    
    /// Returns `self.value` if this result is a .Success, or the given value otherwise. Equivalent with `??`
    func recover(_ value: @autoclosure () -> Value) -> Value {
        return self.value ?? value()
    }

    /// Returns this result if it is a .Success, or the given result otherwise. Equivalent with `??`
    func recover(with result: @autoclosure () -> Result<Value, Error>) -> Result<Value, Error> {
        switch self {
        case .success: return self
        case .failure: return result()
        }
    }
    
    /// Case analysis for Result.
    ///
    /// Returns the value produced by applying `ifFailure` to `failure` Results, or `ifSuccess` to `success` Results.
    func analysis<Result>(ifSuccess: (Value) -> Result, ifFailure: (Error) -> Result) -> Result {
        switch self {
        case let .success(value):
            return ifSuccess(value)
        case let .failure(value):
            return ifFailure(value)
        }
    }
    
    /// The domain for errors constructed by Result.
    static var errorDomain: String { return "com.antitypical.Result" }

    /// The userInfo key for source functions in errors constructed by Result.
    static var functionKey: String { return "\(errorDomain).function" }

    /// The userInfo key for source file paths in errors constructed by Result.
    static var fileKey: String { return "\(errorDomain).file" }

    /// The userInfo key for source file line numbers in errors constructed by Result.
    static var lineKey: String { return "\(errorDomain).line" }
    
    /// Constructs an error.
    static func error(_ message: String? = nil, function: String = #function, file: String = #file, line: Int = #line) -> NSError {
        var userInfo: [String: Any] = [
            functionKey: function,
            fileKey: file,
            lineKey: line,
        ]

        if let message = message {
            userInfo[NSLocalizedDescriptionKey] = message
        }

        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }
    
    /// Constructs a result from an `Optional`, failing with `Error` if `nil`.
    init(_ value: Value?, failWith: @autoclosure () -> Error) {
        self = value.map(Result.success) ?? .failure(failWith())
    }
}
