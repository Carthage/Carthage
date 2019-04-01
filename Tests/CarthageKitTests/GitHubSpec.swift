import Foundation
import Nimble
import Quick

import Tentacle
@testable import CarthageKit

class GitHubSpec: QuickSpec {
	override func spec() {
		describe("Repository.fromIdentifier") {
			it("should parse owner/name form") {
				let identifier = "ReactiveCocoa/ReactiveSwift"
				let result = Repository.fromIdentifier(identifier)
				expect(result.value?.0) == Server.dotCom
				expect(result.value?.1) == Repository(owner: "ReactiveCocoa", name: "ReactiveSwift")
				expect(result.error).to(beNil())
			}

			it("should reject git protocol") {
				let identifier = "git://git@some_host/some_owner/some_repo.git"
				let expected = ScannableError(message: "invalid GitHub repository identifier \"\(identifier)\"")
				let result = Repository.fromIdentifier(identifier)
				expect(result.value).to(beNil())
				expect(result.error) == expected
			}

			it("should reject ssh protocol") {
				let identifier = "ssh://git@some_host/some_owner/some_repo.git"
				let expected = ScannableError(message: "invalid GitHub repository identifier \"\(identifier)\"")
				let result = Repository.fromIdentifier(identifier)
				expect(result.value).to(beNil())
				expect(result.error) == expected
			}
		}
	}
}
