import XCTest
import Nimble

class BeAnInstanceOfTest: XCTestCase {
    func testPositiveMatch() {
        expect(nil as NSNull?).toNot(beAnInstanceOf(NSNull))

        expect(NSNull()).to(beAnInstanceOf(NSNull))
        expect(NSNumber(integer:1)).toNot(beAnInstanceOf(NSDate))
    }

    func testFailureMessages() {
        failsWithErrorMessage("expected <nil> to be an instance of NSString") {
            expect(nil as NSString?).to(beAnInstanceOf(NSString))
        }
        failsWithErrorMessage("expected <__NSCFNumber instance> to be an instance of NSString") {
            expect(NSNumber(integer:1)).to(beAnInstanceOf(NSString))
        }
        failsWithErrorMessage("expected <__NSCFNumber instance> to not be an instance of NSNumber") {
            expect(NSNumber(integer:1)).toNot(beAnInstanceOf(NSNumber))
        }
    }
}
