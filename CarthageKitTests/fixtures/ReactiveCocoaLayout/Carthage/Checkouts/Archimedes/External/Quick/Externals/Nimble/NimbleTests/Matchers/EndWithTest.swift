import XCTest
import Nimble

class EndWithTest: XCTestCase {

    func testEndWithPositives() {
        expect([1, 2, 3]).to(endWith(3))
        expect([1, 2, 3]).toNot(endWith(2))

        expect("foobar").to(endWith("bar"))
        expect("foobar").toNot(endWith("oo"))

        expect(NSString(string: "foobar")).to(endWith("bar"))
        expect(NSString(string: "foobar")).toNot(endWith("oo"))

        expect(NSArray(array: ["a", "b"])).to(endWith("b"))
        expect(NSArray(array: ["a", "b"])).toNot(endWith("a"))
        expect(nil as NSArray?).toNot(endWith("a"))
    }

    func testEndWithNegatives() {
        failsWithErrorMessage("expected <[1, 2, 3]> to end with <2>") {
            expect([1, 2, 3]).to(endWith(2))
        }
        failsWithErrorMessage("expected <[1, 2, 3]> to not end with <3>") {
            expect([1, 2, 3]).toNot(endWith(3))
        }
        failsWithErrorMessage("expected <batman> to end with <atm>") {
            expect("batman").to(endWith("atm"))
        }
        failsWithErrorMessage("expected <batman> to not end with <man>") {
            expect("batman").toNot(endWith("man"))
        }
    }

}
