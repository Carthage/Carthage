import XCTest
import Quick
import Nimble

var beforeSuiteWasExecuted = false

class FunctionalTests_BeforeSuite_BeforeSuiteSpec: QuickSpec {
    override func spec() {
        beforeSuite {
            beforeSuiteWasExecuted = true
        }
    }
}

class FunctionalTests_BeforeSuite_Spec: QuickSpec {
    override func spec() {
        it("is executed after beforeSuite") {
            expect(beforeSuiteWasExecuted).to(beTruthy())
        }
    }
}

class BeforeSuiteTests: XCTestCase {
    func testBeforeSuiteIsExecutedBeforeAnyExamples() {
        // Execute the spec with an assertion before the one with a beforeSuite
        let specs = NSArray(objects: FunctionalTests_BeforeSuite_Spec.classForCoder(),
                                     FunctionalTests_BeforeSuite_BeforeSuiteSpec.classForCoder())
        let result = qck_runSpecs(specs)

        XCTAssert(result.hasSucceeded)
    }
}
