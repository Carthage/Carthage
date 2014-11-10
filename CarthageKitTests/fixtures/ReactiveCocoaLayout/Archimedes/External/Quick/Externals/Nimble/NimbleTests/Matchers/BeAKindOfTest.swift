import XCTest
import Nimble

class TestNull : NSNull {}

class BeAKindOfTest: XCTestCase {
    func testPositiveMatch() {
        expect(nil as NSNull?).toNot(beAKindOf(NSNull))

        expect(TestNull()).to(beAKindOf(NSNull))
        expect(NSObject()).to(beAKindOf(NSObject))
        expect(NSNumber(integer:1)).toNot(beAKindOf(NSDate))
    }

    func testFailureMessages() {
        failsWithErrorMessage("expected <nil> to be a kind of NSString") {
            expect(nil as NSString?).to(beAKindOf(NSString))
        }
        failsWithErrorMessage("expected <__NSCFNumber instance> to be a kind of NSString") {
            expect(NSNumber(integer:1)).to(beAKindOf(NSString))
        }
        failsWithErrorMessage("expected <__NSCFNumber instance> to not be a kind of NSNumber") {
            expect(NSNumber(integer:1)).toNot(beAKindOf(NSNumber))
        }
    }
}
