import XCTest
import Nimble

enum ConvertsToBool : BooleanType, Printable {
    case TrueLike, FalseLike

    var boolValue : Bool {
        switch self {
        case .TrueLike: return true
        case .FalseLike: return false
        }
    }

    var description : String {
        switch self {
        case .TrueLike: return "TrueLike"
        case .FalseLike: return "FalseLike"
        }
    }
}

class BeTruthyTest : XCTestCase {
    func testShouldMatchTrue() {
        expect(true).to(beTruthy())

        failsWithErrorMessage("expected to not be truthy, got <true>") {
            expect(true).toNot(beTruthy())
        }
    }

    func testShouldNotMatchFalse() {
        expect(false).toNot(beTruthy())

        failsWithErrorMessage("expected to be truthy, got <false>") {
            expect(false).to(beTruthy())
        }
    }

    func testShouldNotMatchNilBools() {
        expect(nil as Bool?).toNot(beTruthy())

        failsWithErrorMessage("expected to be truthy, got <nil>") {
            expect(nil as Bool?).to(beTruthy())
        }
    }

    func testShouldMatchBoolConvertibleTypesThatConvertToTrue() {
        expect(ConvertsToBool.TrueLike).to(beTruthy())

        failsWithErrorMessage("expected to not be truthy, got <TrueLike>") {
            expect(ConvertsToBool.TrueLike).toNot(beTruthy())
        }
    }

    func testShouldNotMatchBoolConvertibleTypesThatConvertToFalse() {
        expect(ConvertsToBool.FalseLike).toNot(beTruthy())

        failsWithErrorMessage("expected to be truthy, got <FalseLike>") {
            expect(ConvertsToBool.FalseLike).to(beTruthy())
        }
    }
}

class BeTrueTest : XCTestCase {
    func testShouldMatchTrue() {
        expect(true).to(beTrue())

        failsWithErrorMessage("expected to not be true, got <true>") {
            expect(true).toNot(beTrue())
        }
    }

    func testShouldNotMatchFalse() {
        expect(false).toNot(beTrue())

        failsWithErrorMessage("expected to be true, got <false>") {
            expect(false).to(beTrue())
        }
    }

    func testShouldNotMatchNilBools() {
        expect(nil as Bool?).toNot(beTrue())

        failsWithErrorMessage("expected to be true, got <nil>") {
            expect(nil as Bool?).to(beTrue())
        }
    }
}

class BeFalsyTest : XCTestCase {
    func testShouldNotMatchTrue() {
        expect(true).toNot(beFalsy())

        failsWithErrorMessage("expected to be falsy, got <true>") {
            expect(true).to(beFalsy())
        }
    }

    func testShouldMatchFalse() {
        expect(false).to(beFalsy())

        failsWithErrorMessage("expected to not be falsy, got <false>") {
            expect(false).toNot(beFalsy())
        }
    }

    func testShouldMatchNilBools() {
        expect(nil as Bool?).to(beFalsy())

        failsWithErrorMessage("expected to not be falsy, got <nil>") {
            expect(nil as Bool?).toNot(beFalsy())
        }
    }
}

class BeFalseTest : XCTestCase {
    func testShouldNotMatchTrue() {
        expect(true).toNot(beFalse())

        failsWithErrorMessage("expected to be false, got <true>") {
            expect(true).to(beFalse())
        }
    }

    func testShouldMatchFalse() {
        expect(false).to(beFalse())

        failsWithErrorMessage("expected to not be false, got <false>") {
            expect(false).toNot(beFalse())
        }
    }

    func testShouldNotMatchNilBools() {
        failsWithErrorMessage("expected to be false, got <nil>") {
            expect(nil as Bool?).to(beFalse())
        }

        failsWithErrorMessage("expected to not be false, got <nil>") {
            expect(nil as Bool?).toNot(beFalse())
        }
    }
}
