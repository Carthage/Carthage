import Foundation

public struct MatcherFunc<T>: BasicMatcher {
    public let matcher: (Expression<T>, FailureMessage) -> Bool

    public init(_ matcher: (Expression<T>, FailureMessage) -> Bool) {
        self.matcher = matcher
    }

    public func matches(actualExpression: Expression<T>, failureMessage: FailureMessage) -> Bool {
        return matcher(actualExpression, failureMessage)
    }
}

func _objc(matcher: MatcherFunc<NSObject>) -> NMBObjCMatcher {
    return NMBObjCMatcher { actualExpression, failureMessage, location in
        let expr = Expression(expression: actualExpression, location: location)
        return matcher.matches(expr, failureMessage: failureMessage)
    }
}
