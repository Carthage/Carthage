import Foundation
import Nimble
import Quick
import ReactiveSwift
import Tentacle

import struct Foundation.URL

@testable import CarthageKit

/// - Note: These tests are _not run_ on Travis CI — due to some interference causing them to be flakey (maybe network effects).
///   <!-- -->
///   For additional discussion, visit <https://github.com/Carthage/Carthage/pull/2862>.
class RemoteVersionSpec: QuickSpec {
	override func spec() {
		/// Our exemption here is somewhat heuristic — but, it applies broadly in Xcode
		/// environments, and Swift Package Manager environments, and others.
		if ProcessInfo.processInfo.environment.contains(where: { $0.lowercased() == "user" && $1.lowercased() == "travis" }) { return }

		describe("remoteVersion") {
			it("should time out") {
				var version: SemanticVersion? = SemanticVersion(0, 0, 0)
				DispatchQueue.main.async {
					version = remoteVersion(SignalProducer.never)
				}
				expect(version).notTo(beNil())
				expect(version).toEventually(beNil(), timeout: 0.6)
			}

			it("should return version") {
				let release = Release(id: 0, tag: "0.1.0", url: URL(string: "about:blank")!, assets: [])
				let producer = SignalProducer<Release, CarthageError>(value: release)
				expect(remoteVersion(producer)) == SemanticVersion(0, 1, 0)
			}
		}
	}
}
