import XCTest
import Quick
import Nimble

class Configuration_AfterEachSpec: QuickSpec {
    override func spec() {
        beforeEach {
            FunctionalTests_Configuration_AfterEachWasExecuted = false
        }
        it("is executed before the configuration afterEach") {
            expect(FunctionalTests_Configuration_AfterEachWasExecuted).to(beFalsy())
        }
    }
}

class Configuration_AfterEachTests: XCTestCase {
    override func setUp() {
        super.setUp()
        FunctionalTests_Configuration_AfterEachWasExecuted = false
    }

    override func tearDown() {
        FunctionalTests_Configuration_AfterEachWasExecuted = false
        super.tearDown()
    }

    func testExampleIsRunAfterTheConfigurationBeforeEachIsExecuted() {
        qck_runSpec(Configuration_BeforeEachSpec.classForCoder())
        XCTAssert(FunctionalTests_Configuration_AfterEachWasExecuted)
    }
}
