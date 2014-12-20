import XCTest
import Nimble

class AsyncTest: XCTestCase {

    func testAsyncPolling() {
        var value = 0
        deferToMainQueue { value = 1 }
        expect(value).toEventually(equal(1))

        deferToMainQueue { value = 0 }
        expect(value).toEventuallyNot(equal(1))

        failsWithErrorMessage("expected to eventually not equal <0>, got <0>") {
            expect(value).toEventuallyNot(equal(0))
        }
        failsWithErrorMessage("expected to eventually equal <1>, got <0>") {
            expect(value).toEventually(equal(1))
        }
    }

    func testAsyncCallback() {
        waitUntil { done in
            done()
        }
        waitUntil { done in
            deferToMainQueue {
                done()
            }
        }
        failsWithErrorMessage("Waited more than 1.0 second") {
            waitUntil(timeout: 1) { done in return }
        }
        failsWithErrorMessage("Waited more than 0.01 seconds") {
            waitUntil(timeout: 0.01) { done in
                NSThread.sleepForTimeInterval(0.1)
                done()
            }
        }

        failsWithErrorMessage("expected to equal <2>, got <1>") {
            waitUntil { done in
                NSThread.sleepForTimeInterval(0.1)
                expect(1).to(equal(2))
                done()
            }
        }
    }
}
