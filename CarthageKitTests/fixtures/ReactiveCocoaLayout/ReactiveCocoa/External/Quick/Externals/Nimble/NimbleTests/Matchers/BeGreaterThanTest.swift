import XCTest
import Nimble

class BeGreaterThanTest: XCTestCase {
    func testGreaterThan() {
        expect(10).to(beGreaterThan(2))
        expect(1).toNot(beGreaterThan(2))
        expect(NSNumber(int:3)).to(beGreaterThan(2))
        expect(NSNumber(int:1)).toNot(beGreaterThan(NSNumber(int:2)))

        failsWithErrorMessage("expected to be greater than <2>, got <0>") {
            expect(0).to(beGreaterThan(2))
            return
        }
        failsWithErrorMessage("expected to not be greater than <0>, got <1>") {
            expect(1).toNot(beGreaterThan(0))
            return
        }
    }

    func testGreaterThanOperator() {
        expect(1) > 0
        expect(NSNumber(int:1)) > NSNumber(int:0)
        expect(NSNumber(int:1)) > 0

        failsWithErrorMessage("expected to be greater than <2.0000>, got <1.0000>") {
            expect(1) > 2
            return
        }
    }
}
