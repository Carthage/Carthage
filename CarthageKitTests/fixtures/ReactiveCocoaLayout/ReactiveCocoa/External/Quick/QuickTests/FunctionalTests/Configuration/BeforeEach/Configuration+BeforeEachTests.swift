import XCTest
import Quick
import Nimble

class Configuration_BeforeEachSpec: QuickSpec {
    override func spec() {
        it("is executed after the configuration beforeEach") {
            expect(FunctionalTests_Configuration_BeforeEachWasExecuted).to(beTruthy())
        }
    }
}

class Configuration_BeforeEachTests: XCTestCase {
    override func setUp() {
        super.setUp()
        FunctionalTests_Configuration_BeforeEachWasExecuted = false
    }

    override func tearDown() {
        FunctionalTests_Configuration_BeforeEachWasExecuted = false
        super.tearDown()
    }

    func testExampleIsRunAfterTheConfigurationBeforeEachIsExecuted() {
        qck_runSpec(Configuration_BeforeEachSpec.classForCoder())
        XCTAssert(FunctionalTests_Configuration_BeforeEachWasExecuted)
    }
}
