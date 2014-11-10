import XCTest
import Quick
import Nimble

class FunctionalTests_SharedExamples_Spec: QuickSpec {
    override func spec() {
        itBehavesLike("a group of three shared examples")
    }
}

class FunctionalTests_SharedExamples_ContextSpec: QuickSpec {
    override func spec() {
        itBehavesLike("shared examples that take a context") { ["callsite": "SharedExamplesSpec"] }
    }
}

// Shared examples are defined in QuickTests/Fixtures
class SharedExamplesTests: XCTestCase {
    func testAGroupOfThreeSharedExamplesExecutesThreeExamples() {
        let result = qck_runSpec(FunctionalTests_SharedExamples_Spec.classForCoder())
        XCTAssert(result.hasSucceeded)
        XCTAssertEqual(result.executionCount, 3 as UInt)
    }

    func testSharedExamplesWithContextPassContextToExamples() {
        let result = qck_runSpec(FunctionalTests_SharedExamples_ContextSpec.classForCoder())
        XCTAssert(result.hasSucceeded)
    }
}
