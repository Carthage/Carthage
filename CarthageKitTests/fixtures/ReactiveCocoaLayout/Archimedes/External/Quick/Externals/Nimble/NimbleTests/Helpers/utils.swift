import Foundation
import Nimble
import XCTest

func failsWithErrorMessage(message: String, closure: () -> Void, file: String = __FILE__, line: Int = __LINE__) {
    let recorder = AssertionRecorder()
    withAssertionHandler(recorder, closure)

    var lastFailureMessage: String?
    if recorder.assertions.count > 0 {
        lastFailureMessage = recorder.assertions[recorder.assertions.endIndex - 1].message
        if lastFailureMessage == message {
            return
        }
    }
    if lastFailureMessage != nil {
        let msg = "Got failure message: '\(lastFailureMessage!)', but expected '\(message)'"
        XCTFail(msg, file: file, line: UInt(line))
    } else {
        XCTFail("expected failure message, but got none", file: file, line: UInt(line))
    }
}

func deferToMainQueue(action: () -> Void) {
    dispatch_async(dispatch_get_main_queue()) {
        NSThread.sleepForTimeInterval(0.01)
        action()
    }
}
