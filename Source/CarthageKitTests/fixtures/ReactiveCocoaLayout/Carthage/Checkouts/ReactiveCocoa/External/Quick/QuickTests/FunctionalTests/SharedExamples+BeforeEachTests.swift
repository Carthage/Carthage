import XCTest
import Quick
import Nimble

var specBeforeEachExecutedCount = 0
var sharedExamplesBeforeEachExecutedCount = 0

class FunctionalTests_SharedExamples_BeforeEachTests_SharedExamples: QuickConfiguration {
    override class func configure(configuration: Configuration) {
        sharedExamples("a group of three shared examples with a beforeEach") {
            beforeEach { sharedExamplesBeforeEachExecutedCount += 1 }
            it("passes once") {}
            it("passes twice") {}
            it("passes three times") {}
        }
    }
}

class FunctionalTests_SharedExamples_BeforeEachSpec: QuickSpec {
    override func spec() {
        beforeEach { specBeforeEachExecutedCount += 1 }
        it("executes the spec beforeEach once") {}
        itBehavesLike("a group of three shared examples with a beforeEach")
    }
}

class SharedExamples_BeforeEachTests: XCTestCase {
    override func setUp() {
        super.setUp()
        specBeforeEachExecutedCount = 0
        sharedExamplesBeforeEachExecutedCount = 0
    }

    override func tearDown() {
        specBeforeEachExecutedCount = 0
        sharedExamplesBeforeEachExecutedCount = 0
        super.tearDown()
    }

    func testBeforeEachOutsideOfSharedExamplesExecutedOnceBeforeEachExample() {
        qck_runSpec(FunctionalTests_SharedExamples_BeforeEachSpec.classForCoder())
        XCTAssertEqual(specBeforeEachExecutedCount, 4)
    }

    func testBeforeEachInSharedExamplesExecutedOnceBeforeEachSharedExample() {
        qck_runSpec(FunctionalTests_SharedExamples_BeforeEachSpec.classForCoder())
        XCTAssertEqual(sharedExamplesBeforeEachExecutedCount, 3)
    }
}
