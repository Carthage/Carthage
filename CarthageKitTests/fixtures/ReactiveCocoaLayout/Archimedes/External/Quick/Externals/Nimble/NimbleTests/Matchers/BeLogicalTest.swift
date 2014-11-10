import XCTest
import Nimble

class BeLogicalTest: XCTestCase {
    func testBeTruthy() {
        expect(true).to(beTruthy())
        expect(false).toNot(beTruthy())

        failsWithErrorMessage("expected <false> to be truthy") {
            expect(false).to(beTruthy())
        }
    }
    func testBeFalsy() {
        expect(false).to(beFalsy())
        expect(true).toNot(beFalsy())

        failsWithErrorMessage("expected <true> to be falsy") {
            expect(true).to(beFalsy())
        }
    }
}
