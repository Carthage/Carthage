import Foundation
import Nimble
import Quick
import ReactiveSwift
import Tentacle
import Utility
import XCTest

import struct Foundation.URL

@testable import CarthageKit

class RemoteVersionSpec: QuickSpec {
	override func spec() {
		describe("remoteVersion") {
			it("should return version") {
                guard let aboutURL = URL(string: "about:blank") else {
                    fail("Expected aboutURL to not be nil")
                    return
                }
				let release = Release(id: 0, tag: "0.1.0", url: aboutURL, assets: [])
				let producer = SignalProducer<Release, CarthageError>(value: release)
				expect(remoteVersion(producer)) == Version(0, 1, 0)
			}
		}
	}
}

class RemoteVersionTests: XCTestCase {
    func testVersionTimeout() {
        let expectation = XCTestExpectation(description: "timeout")
        var version: Version? = Version(0, 0, 0)
        DispatchQueue.main.async {
            version = remoteVersion(SignalProducer.never)
            XCTAssertNil(version)
            expectation.fulfill()
        }
        XCTAssertNotNil(version)
        wait(for: [expectation], timeout: 0.6)
    }
}
