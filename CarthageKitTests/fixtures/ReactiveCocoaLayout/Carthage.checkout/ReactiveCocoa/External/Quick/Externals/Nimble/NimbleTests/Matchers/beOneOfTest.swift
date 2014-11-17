import XCTest
import Nimble

class beOneOfTest: XCTestCase {
    func testPositiveMatches() {
        expect(1).to(beOneOf([1, 2, 3]))
        expect(4).toNot(beOneOf([1, 2, 3]))

        expect(1 as CInt).to(beOneOf([1, 2, 3]))
        expect(4 as CInt).toNot(beOneOf([1, 2, 3]))

        expect(NSString(string: "a")).to(beOneOf(["a", "b", "c"]))
        expect(NSString(string: "d")).toNot(beOneOf(["a", "b", "c"]))
    }

    func testNegativeMatches() {
        failsWithErrorMessage("expected to not be one of: [1, 2, 3], got <1>") {
            expect(1).toNot(beOneOf([1, 2, 3]))
        }
        failsWithErrorMessage("expected to be one of: [1, 2, 3], got <4>") {
            expect(4).to(beOneOf([1, 2, 3]))
        }
    }
}
