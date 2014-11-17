import XCTest
import Nimble

class RaisesExceptionTest: XCTestCase {
    var exception = NSException(name: "laugh", reason: "Lulz", userInfo: nil)

    func testCapturingInAutoClosure() {
        expect(exception.raise()).to(raiseException(named: "laugh"))
        expect(exception.raise()).to(raiseException())

        failsWithErrorMessage("expected to raise exception named <foo>") {
            expect(self.exception.raise()).to(raiseException(named: "foo"))
        }
    }

    func testCapturingInExplicitClosure() {
        expect {
            self.exception.raise()
        }.to(raiseException(named: "laugh"))

        expect {
            self.exception.raise()
        }.to(raiseException())
    }

    func testCapturingWithReason() {
        expect(exception.raise()).to(raiseException(named: "laugh", reason: "Lulz"))

        failsWithErrorMessage("expected to raise any exception") {
            expect(self.exception).to(raiseException())
        }
        failsWithErrorMessage("expected to not raise any exception") {
            expect(self.exception.raise()).toNot(raiseException())
        }
        failsWithErrorMessage("expected to raise exception named <laugh> and reason <Lulz>") {
            expect(self.exception).to(raiseException(named: "laugh", reason: "Lulz"))
        }

        failsWithErrorMessage("expected to raise exception named <bar> and reason <Lulz>") {
            expect(self.exception.raise()).to(raiseException(named: "bar", reason: "Lulz"))
        }
        failsWithErrorMessage("expected to not raise exception named <laugh>") {
            expect(self.exception.raise()).toNot(raiseException(named: "laugh"))
        }
        failsWithErrorMessage("expected to not raise exception named <laugh> and reason <Lulz>") {
            expect(self.exception.raise()).toNot(raiseException(named: "laugh", reason: "Lulz"))
        }
    }
}
