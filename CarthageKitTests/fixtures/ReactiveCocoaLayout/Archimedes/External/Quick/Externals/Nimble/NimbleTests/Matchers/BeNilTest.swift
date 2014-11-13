import XCTest
import Nimble

class BeNilTest: XCTestCase {
    func producesNil() -> Array<Int>? {
        return nil
    }

    func testBeNil() {
        expect(nil as Int?).to(beNil())
        expect(1 as Int?).toNot(beNil())
        expect(producesNil()).to(beNil())

        failsWithErrorMessage("expected <nil> to not be nil") {
            expect(nil as Int?).toNot(beNil())
        }

        failsWithErrorMessage("expected <1> to be nil") {
            expect(1 as Int?).to(beNil())
        }
    }
}
