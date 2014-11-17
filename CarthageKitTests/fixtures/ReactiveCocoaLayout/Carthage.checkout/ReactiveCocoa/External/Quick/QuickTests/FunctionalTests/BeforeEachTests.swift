import XCTest
import Quick
import Nimble

var outerBeforeEachExecutedCount = 0
var innerBeforeEachExecutedCount = 0
var noExamplesBeforeEachExecutedCount = 0

class FunctionalTests_BeforeEachSpec: QuickSpec {
    override func spec() {
        beforeEach { outerBeforeEachExecutedCount += 1 }
        it("executes the outer beforeEach once") {}
        it("executes the outer beforeEach a second time") {}

        context("when there are nested beforeEach") {
            beforeEach { innerBeforeEachExecutedCount += 1 }
            it("executes the outer and inner beforeEach") {}
        }

        context("when there are nested beforeEach without examples") {
            beforeEach { noExamplesBeforeEachExecutedCount += 1 }
        }
    }
}

class BeforeEachTests: XCTestCase {
    override func setUp() {
        super.setUp()
        outerBeforeEachExecutedCount = 0
        innerBeforeEachExecutedCount = 0
        noExamplesBeforeEachExecutedCount = 0
    }

    override func tearDown() {
        outerBeforeEachExecutedCount = 0
        innerBeforeEachExecutedCount = 0
        noExamplesBeforeEachExecutedCount = 0
        super.tearDown()
    }

    func testOuterBeforeEachIsExecutedOnceBeforeEachExample() {
        qck_runSpec(FunctionalTests_BeforeEachSpec.classForCoder())
        XCTAssertEqual(outerBeforeEachExecutedCount, 3)
    }

    func testInnerBeforeEachIsExecutedOnceBeforeEachInnerExample() {
        qck_runSpec(FunctionalTests_BeforeEachSpec.classForCoder())
        XCTAssertEqual(innerBeforeEachExecutedCount, 1)
    }

    func testNoExamplesBeforeEachIsNeverExecuted() {
        qck_runSpec(FunctionalTests_BeforeEachSpec.classForCoder())
        XCTAssertEqual(noExamplesBeforeEachExecutedCount, 0)
    }
}
