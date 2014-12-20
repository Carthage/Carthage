import XCTest
import Nimble

class ContainTest: XCTestCase {
    func testContain() {
        expect([1, 2, 3]).to(contain(1))
        expect([1, 2, 3] as [CInt]).to(contain(1 as CInt))
        expect([1, 2, 3] as Array<CInt>).to(contain(1 as CInt))
        expect(["foo", "bar", "baz"]).to(contain("baz"))
        expect([1, 2, 3]).toNot(contain(4))
        expect(["foo", "bar", "baz"]).toNot(contain("ba"))
        expect(NSArray(array: ["a"])).to(contain("a"))
        expect(NSArray(array: ["a"])).toNot(contain("b"))
        expect(NSArray(object: 1) as NSArray?).to(contain(1))
        expect(nil as NSArray?).toNot(contain(1))

        failsWithErrorMessage("expected <[a, b, c]> to contain <bar>") {
            expect(["a", "b", "c"]).to(contain("bar"))
        }
        failsWithErrorMessage("expected <[a, b, c]> to not contain <b>") {
            expect(["a", "b", "c"]).toNot(contain("b"))
        }
    }

    func testContainSubstring() {
        expect("foo").to(contain("o"))
        expect("foo").to(contain("oo"))
        expect("foo").toNot(contain("z"))
        expect("foo").toNot(contain("zz"))

        failsWithErrorMessage("expected <foo> to contain <bar>") {
            expect("foo").to(contain("bar"))
        }
        failsWithErrorMessage("expected <foo> to not contain <oo>") {
            expect("foo").toNot(contain("oo"))
        }
    }

    func testContainObjCSubstring() {
        let str = NSString(string: "foo")
        expect(str).to(contain(NSString(string: "o")))
        expect(str).to(contain(NSString(string: "oo")))
        expect(str).toNot(contain(NSString(string: "z")))
        expect(str).toNot(contain(NSString(string: "zz")))
    }

    func testVariadicArguments() {
        expect([1, 2, 3]).to(contain(1, 2))
        expect([1, 2, 3]).toNot(contain(1, 4))

        failsWithErrorMessage("expected <[a, b, c]> to contain <a, bar>") {
            expect(["a", "b", "c"]).to(contain("a", "bar"))
        }

        failsWithErrorMessage("expected <[a, b, c]> to not contain <bar, b>") {
            expect(["a", "b", "c"]).toNot(contain("bar", "b"))
        }
    }
}
