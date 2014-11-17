import XCTest
import Nimble

class BeginWithTest: XCTestCase {

    func testPositiveMatches() {
        expect([1, 2, 3]).to(beginWith(1))
        expect([1, 2, 3]).toNot(beginWith(2))

        expect("foobar").to(beginWith("foo"))
        expect("foobar").toNot(beginWith("oo"))

        expect(NSString(string: "foobar")).to(beginWith("foo"))
        expect(NSString(string: "foobar")).toNot(beginWith("oo"))

        expect(NSArray(array: ["a", "b"])).to(beginWith("a"))
        expect(NSArray(array: ["a", "b"])).toNot(beginWith("b"))
        expect(nil as NSArray?).toNot(beginWith("b"))
    }

    func testNegativeMatches() {
        failsWithErrorMessage("expected <[1, 2, 3]> to begin with <2>") {
            expect([1, 2, 3]).to(beginWith(2))
        }
        failsWithErrorMessage("expected <[1, 2, 3]> to not begin with <1>") {
            expect([1, 2, 3]).toNot(beginWith(1))
        }
        failsWithErrorMessage("expected <batman> to begin with <atm>") {
            expect("batman").to(beginWith("atm"))
        }
        failsWithErrorMessage("expected <batman> to not begin with <bat>") {
            expect("batman").toNot(beginWith("bat"))
        }
    }

}
