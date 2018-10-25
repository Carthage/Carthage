import Foundation
import Nimble
import Quick
import ReactiveSwift
import Tentacle

@testable import CarthageKit

class RemoteVersionSpec: QuickSpec {
	override func spec() {
		describe("remoteVersion") {
			it("should time out") {
				var version: SemanticVersion? = SemanticVersion(major: 0, minor: 0, patch: 0)
				DispatchQueue.main.async {
					version = remoteVersion(SignalProducer.never)
				}
				expect(version).notTo(beNil())
				expect(version).toEventually(beNil(), timeout: 0.6)
			}

			it("should return version") {
				let release = Release(id: 0, tag: "0.1.0", url: URL(string: "about:blank")!, assets: [])
				let producer = SignalProducer<Release, CarthageError>(value: release)
				expect(remoteVersion(producer)) == SemanticVersion(major: 0, minor: 1, patch: 0)
			}
		}
	}
}
