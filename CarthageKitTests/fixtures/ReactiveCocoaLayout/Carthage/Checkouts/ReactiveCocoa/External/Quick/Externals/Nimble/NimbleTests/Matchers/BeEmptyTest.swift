import XCTest
import Nimble

class BeEmptyTest: XCTestCase {
    func testBeEmptyPositive() {
        expect(nil as NSString?).to(beEmpty())
        expect(nil as [CInt]?).to(beEmpty())

        expect([]).to(beEmpty())
        expect([1]).toNot(beEmpty())

        expect([] as [CInt]).to(beEmpty())
        expect([1] as [CInt]).toNot(beEmpty())

        expect(NSDictionary()).to(beEmpty())
        expect(NSDictionary(object: 1, forKey: 1)).toNot(beEmpty())

        expect(Dictionary<Int, Int>()).to(beEmpty())
        expect(["hi": 1]).toNot(beEmpty())

        expect(NSArray()).to(beEmpty())
        expect(NSArray(array: [1])).toNot(beEmpty())

        expect(NSSet()).to(beEmpty())
        expect(NSSet(array: [1])).toNot(beEmpty())

        expect(NSString()).to(beEmpty())
        expect(NSString(string: "hello")).toNot(beEmpty())

        expect("").to(beEmpty())
        expect("foo").toNot(beEmpty())
    }

    func testBeEmptyNegative() {
        failsWithErrorMessage("expected to not be empty, got <()>") {
            expect([]).toNot(beEmpty())
        }
        failsWithErrorMessage("expected to be empty, got <[1]>") {
            expect([1]).to(beEmpty())
        }

        failsWithErrorMessage("expected to not be empty, got <>") {
            expect("").toNot(beEmpty())
        }
        failsWithErrorMessage("expected to be empty, got <foo>") {
            expect("foo").to(beEmpty())
        }
    }
}
