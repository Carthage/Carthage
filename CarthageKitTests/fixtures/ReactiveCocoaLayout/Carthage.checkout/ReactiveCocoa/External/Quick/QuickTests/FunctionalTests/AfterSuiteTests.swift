import XCTest
import Quick
import Nimble

var afterSuiteWasExecuted = false

class FunctionalTests_AfterSuite_AfterSuiteSpec: QuickSpec {
    override func spec() {
        afterSuite {
            afterSuiteWasExecuted = true
        }
    }
}

class FunctionalTests_AfterSuite_Spec: QuickSpec {
    override func spec() {
        it("is executed before afterSuite") {
            expect(afterSuiteWasExecuted).to(beFalsy())
        }
    }
}

class AfterSuiteTests: XCTestCase {
    func testAfterSuiteIsNotExecutedBeforeAnyExamples() {
        // Execute the spec with an assertion after the one with an afterSuite.
        let specs = NSArray(objects: FunctionalTests_AfterSuite_AfterSuiteSpec.classForCoder(),
                                     FunctionalTests_AfterSuite_Spec.classForCoder())
        let result = qck_runSpecs(specs)

        // Although this ensures that afterSuite is not called before any
        // examples, it doesn't test that it's ever called in the first place.
        XCTAssert(result.hasSucceeded)
    }
}
