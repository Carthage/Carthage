import XCTest
import Quick
import Nimble

var outerAfterEachExecutedCount = 0
var innerAfterEachExecutedCount = 0
var noExamplesAfterEachExecutedCount = 0

class FunctionalTests_AfterEachSpec: QuickSpec {
    override func spec() {
        beforeEach { outerAfterEachExecutedCount += 1 }
        it("executes the outer afterEach once") {}
        it("executes the outer afterEach a second time") {}

        context("when there are nested beforeEach") {
            beforeEach { innerAfterEachExecutedCount += 1 }
            it("executes the outer and inner afterEach") {}
        }

        context("when there are nested afterEach without examples") {
            beforeEach { noExamplesAfterEachExecutedCount += 1 }
        }
    }
}

class AfterEachTests: XCTestCase {
    override func setUp() {
        super.setUp()
        outerAfterEachExecutedCount = 0
        innerAfterEachExecutedCount = 0
        noExamplesAfterEachExecutedCount = 0
    }

    override func tearDown() {
        outerAfterEachExecutedCount = 0
        innerAfterEachExecutedCount = 0
        noExamplesAfterEachExecutedCount = 0
        super.tearDown()
    }

    func testOuterAfterEachIsExecutedOnceAfterEachExample() {
        qck_runSpec(FunctionalTests_AfterEachSpec.classForCoder())
        XCTAssertEqual(outerAfterEachExecutedCount, 3)
    }

    func testInnerAfterEachIsExecutedOnceAfterEachInnerExample() {
        qck_runSpec(FunctionalTests_AfterEachSpec.classForCoder())
        XCTAssertEqual(innerAfterEachExecutedCount, 1)
    }

    func testNoExamplesAfterEachIsNeverExecuted() {
        qck_runSpec(FunctionalTests_AfterEachSpec.classForCoder())
        XCTAssertEqual(noExamplesAfterEachExecutedCount, 0)
    }
}
