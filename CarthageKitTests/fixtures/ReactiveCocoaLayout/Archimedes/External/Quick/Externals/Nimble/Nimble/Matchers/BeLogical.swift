import Foundation

public struct _BeBooleanTypeMatcher: BasicMatcher {
    public let expectedValue: BooleanType
    public let stringValue: String

    public func matches(actualExpression: Expression<BooleanType>, failureMessage: FailureMessage) -> Bool {
        failureMessage.postfixMessage = "be \(stringValue)"
        return actualExpression.evaluate()?.boolValue == expectedValue.boolValue
    }
}

public struct _BeBoolMatcher: BasicMatcher {
    public let expectedValue: BooleanType
    public let stringValue: String

    public func matches(actualExpression: Expression<Bool>, failureMessage: FailureMessage) -> Bool {
        failureMessage.postfixMessage = "be \(stringValue)"
        let actual = actualExpression.evaluate()
        return (actual?.boolValue) == expectedValue.boolValue
    }
}

public func beTruthy() -> _BeBooleanTypeMatcher {
    return _BeBooleanTypeMatcher(expectedValue: true, stringValue: "truthy")
}

public func beFalsy() -> _BeBooleanTypeMatcher {
    return _BeBooleanTypeMatcher(expectedValue: false, stringValue: "falsy")
}

public func beTruthy() -> _BeBoolMatcher {
    return _BeBoolMatcher(expectedValue: true, stringValue: "truthy")
}

public func beFalsy() -> _BeBoolMatcher {
    return _BeBoolMatcher(expectedValue: false, stringValue: "falsy")
}

extension NMBObjCMatcher {
    public class func beTruthyMatcher() -> NMBObjCMatcher {
        return NMBObjCMatcher { actualBlock, failureMessage, location in
            let block = ({ (actualBlock() as? NSNumber)?.boolValue ?? false })
            let expr = Expression(expression: block, location: location)
            return beTruthy().matches(expr, failureMessage: failureMessage)
        }
    }
    public class func beFalsyMatcher() -> NMBObjCMatcher {
        return NMBObjCMatcher { actualBlock, failureMessage, location in
            let block = ({ (actualBlock() as? NSNumber)?.boolValue ?? false })
            let expr = Expression(expression: block, location: location)
            return beFalsy().matches(expr, failureMessage: failureMessage)
        }
    }
}
