import XCTest
import Nimble

class BeCloseToTest: XCTestCase {
    func testBeCloseTo() {
        expect(1.2).to(beCloseTo(1.2001))
        expect(1.2 as CDouble).to(beCloseTo(1.2001))
        expect(1.2 as Float).to(beCloseTo(1.2001))

        failsWithErrorMessage("expected <1.2000> to not be close to <1.2001> (within 0.0001)") {
            expect(1.2).toNot(beCloseTo(1.2001))
        }
    }

    func testBeCloseToWithin() {
        expect(1.2).to(beCloseTo(9.300, within: 10))

        failsWithErrorMessage("expected <1.2000> to not be close to <1.2001> (within 1.0000)") {
            expect(1.2).toNot(beCloseTo(1.2001, within: 1.0))
        }
    }

    func testBeCloseToWithNSNumber() {
        expect(NSNumber(double:1.2)).to(beCloseTo(9.300, within: 10))
        expect(NSNumber(double:1.2)).to(beCloseTo(NSNumber(double:9.300), within: 10))
        expect(1.2).to(beCloseTo(NSNumber(double:9.300), within: 10))

        failsWithErrorMessage("expected <1.2000> to not be close to <1.2001> (within 1.0000)") {
            expect(NSNumber(double:1.2)).toNot(beCloseTo(1.2001, within: 1.0))
        }
    }
}
