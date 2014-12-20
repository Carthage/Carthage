import XCTest
import Quick
import Nimble

var oneExampleBeforeEachExecutedCount = 0
var onlyPendingExamplesBeforeEachExecutedCount = 0

class FunctionalTests_PendingSpec: QuickSpec {
    override func spec() {
        pending("an example that will not run") {
            expect(true).to(beFalsy())
        }

        describe("a describe block containing only one enabled example") {
            beforeEach { oneExampleBeforeEachExecutedCount += 1 }
            it("an example that will run") {}
            pending("an example that will not run") {}
        }

        describe("a describe block containing only pending examples") {
            beforeEach { onlyPendingExamplesBeforeEachExecutedCount += 1 }
            pending("an example that will not run") {}
        }
    }
}

class PendingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        oneExampleBeforeEachExecutedCount = 0
        onlyPendingExamplesBeforeEachExecutedCount = 0
    }

    override func tearDown() {
        oneExampleBeforeEachExecutedCount = 0
        onlyPendingExamplesBeforeEachExecutedCount = 0
        super.tearDown()
    }

    func testAnOtherwiseFailingExampleWhenMarkedPendingDoesNotCauseTheSuiteToFail() {
        let result = qck_runSpec(FunctionalTests_PendingSpec.classForCoder())
        XCTAssert(result.hasSucceeded)
    }

    func testBeforeEachOnlyRunForEnabledExamples() {
        qck_runSpec(FunctionalTests_PendingSpec.classForCoder())
        XCTAssertEqual(oneExampleBeforeEachExecutedCount, 1)
    }

    func testBeforeEachDoesNotRunForContextsWithOnlyPendingExamples() {
        qck_runSpec(FunctionalTests_PendingSpec.classForCoder())
        XCTAssertEqual(onlyPendingExamplesBeforeEachExecutedCount, 0)
    }
}
