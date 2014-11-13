import XCTest
import Nimble

class EqualTest: XCTestCase {
    func testEquality() {
        expect(1 as CInt).to(equal(1 as CInt))
        expect(1 as CInt).to(equal(1))
        expect(1).to(equal(1))
        expect("hello").to(equal("hello"))
        expect("hello").toNot(equal("world"))

        expect {
            1
        }.to(equal(1))

        failsWithErrorMessage("expected <hello> to equal <world>") {
            expect("hello").to(equal("world"))
        }
        failsWithErrorMessage("expected <hello> to not equal <hello>") {
            expect("hello").toNot(equal("hello"))
        }
    }

    func testArrayEquality() {
        expect([1, 2, 3]).to(equal([1, 2, 3]))
        expect([1, 2, 3]).toNot(equal([1, 2]))
        expect([1, 2, 3]).toNot(equal([1, 2, 4]))

        let array1: Array<Int> = [1, 2, 3]
        let array2: Array<Int> = [1, 2, 3]
        expect(array1).to(equal(array2))
        expect(array1).to(equal([1, 2, 3]))
        expect(array1).toNot(equal([1, 2] as Array<Int>))

        expect(NSArray(array: [1, 2, 3])).to(equal(NSArray(array: [1, 2, 3])))

        failsWithErrorMessage("expected <[1, 2, 3]> to equal <[1, 2]>") {
            expect([1, 2, 3]).to(equal([1, 2]))
        }
    }

    func testDoesNotMatchNils() {
        failsWithErrorMessage("expected <nil> to equal <nil> (will not match nils, use beNil() instead)") {
            expect(nil as String?).to(equal(nil as String?))
        }
        failsWithErrorMessage("expected <foo> to not equal <nil> (will not match nils, use beNil() instead)") {
            expect("foo").toNot(equal(nil as String?))
        }
        failsWithErrorMessage("expected <nil> to not equal <bar> (will not match nils, use beNil() instead)") {
            expect(nil as String?).toNot(equal("bar"))
        }

        failsWithErrorMessage("expected <nil> to equal <nil> (will not match nils, use beNil() instead)") {
            expect(nil as [Int]?).to(equal(nil as [Int]?))
        }
        failsWithErrorMessage("expected <nil> to not equal <[1]> (will not match nils, use beNil() instead)") {
            expect(nil as [Int]?).toNot(equal([1]))
        }
        failsWithErrorMessage("expected <[1]> to not equal <nil> (will not match nils, use beNil() instead)") {
            expect([1]).toNot(equal(nil as [Int]?))
        }

        failsWithErrorMessage("expected <nil> to equal <nil> (will not match nils, use beNil() instead)") {
            expect(nil as [Int: Int]?).to(equal(nil as [Int: Int]?))
        }
        failsWithErrorMessage("expected <nil> to not equal <[1: 1]> (will not match nils, use beNil() instead)") {
            expect(nil as [Int: Int]?).toNot(equal([1: 1]))
        }
        failsWithErrorMessage("expected <[1: 1]> to not equal <nil> (will not match nils, use beNil() instead)") {
            expect([1: 1]).toNot(equal(nil as [Int: Int]?))
        }
    }

    func testDictionaryEquality() {
        expect(["foo": "bar"]).to(equal(["foo": "bar"]))
        expect(["foo": "bar"]).toNot(equal(["foo": "baz"]))

        let actual = ["foo": "bar"]
        let expected = ["foo": "bar"]
        let unexpected = ["foo": "baz"]
        expect(actual).to(equal(expected))
        expect(actual).toNot(equal(unexpected))

        expect(NSDictionary(object: "bar", forKey: "foo")).to(equal(["foo": "bar"]))
        expect(NSDictionary(object: "bar", forKey: "foo")).to(equal(expected))
    }

    func testNSObjectEquality() {
        expect(NSNumber(integer:1)).to(equal(NSNumber(integer:1)))
        expect(NSNumber(integer:1)) == NSNumber(integer:1)
        expect(NSNumber(integer:1)) != NSNumber(integer:2)
        expect { NSNumber(integer:1) }.to(equal(1))
    }

    func testOperatorEquality() {
        expect("foo") == "foo"
        expect("foo") != "bar"

        failsWithErrorMessage("expected <hello> to equal <world>") {
            expect("hello") == "world"
            return
        }
        failsWithErrorMessage("expected <hello> to not equal <hello>") {
            expect("hello") != "hello"
            return
        }
    }

    func testOperatorEqualityWithArrays() {
        let array1: Array<Int> = [1, 2, 3]
        let array2: Array<Int> = [1, 2, 3]
        let array3: Array<Int> = [1, 2]
        expect(array1) == array2
        expect(array1) != array3
    }

    func testOperatorEqualityWithDictionaries() {
        let dict1 = ["foo": "bar"]
        let dict2 = ["foo": "bar"]
        let dict3 = ["foo": "baz"]
        expect(dict1) == dict2
        expect(dict1) != dict3
    }

    func testOptionalEquality() {
        expect(1 as CInt?).to(equal(1))
        expect(1 as CInt?).to(equal(1 as CInt?))
        expect(nil as NSObject?).toNot(equal(1))

        expect(1).toNot(equal(nil))
    }
}
