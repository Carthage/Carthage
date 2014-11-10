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
        failsWithErrorMessage("expected to be a kind of NSString, got <nil>") {
            expect(nil as NSString?).to(beAKindOf(NSString))
        }
        failsWithErrorMessage("expected to be a kind of NSString, got <__NSCFNumber instance>") {
            expect(NSNumber(integer:1)).to(beAKindOf(NSString))
        }
        failsWithErrorMessage("expected to not be a kind of NSNumber, got <__NSCFNumber instance>") {
            expect(NSNumber(integer:1)).toNot(beAKindOf(NSNumber))
        }
    }
}
