import Foundation
import Nimble
import Quick
import ReactiveSwift
import Tentacle
import Utility

import struct Foundation.URL

@testable import CarthageKit

class RemoteVersionSpec: QuickSpec {
	override func spec() {
		describe("remoteVersion") {
			it("should time out") {
				var version: Version? = Version(0, 0, 0)
				DispatchQueue.main.async {
					version = remoteVersion(SignalProducer.never)
				}
				expect(version).notTo(beNil())
				expect(version).toEventually(beNil(), timeout: 0.6)
			}

			it("should return version") {
				let release = Release(id: 0, tag: "0.1.0", url: URL(string: "about:blank")!, assets: [])
				let producer = SignalProducer<Release, CarthageError>(value: release)
				expect(remoteVersion(producer)) == Version(0, 1, 0)
			}
		}
	}
}
