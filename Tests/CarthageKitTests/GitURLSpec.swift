import Foundation
import Nimble
import Quick

@testable import CarthageKit

class GitURLSpec: QuickSpec {
	override func spec() {
		describe("GitURL") {
			describe("normalizedURLString") {
				it("should parse normal URL") {
					let expected = "github.com/antitypical/Result"
					expect(GitURL("https://github.com/antitypical/Result.git").normalizedURLString) == expected
					expect(GitURL("https://user:password@github.com:443/antitypical/Result").normalizedURLString) == expected
				}

				it("should parse local absolute path") {
					let expected = "/path/to/git/repo"
					expect(GitURL("/path/to/git/repo.git").normalizedURLString) == expected
					expect(GitURL("/path/to/git/repo").normalizedURLString) == expected
				}

				it("should parse local relative path") {
					do {
						let expected = "path/to/git/repo"
						expect(GitURL("path/to/git/repo.git").normalizedURLString) == expected
						expect(GitURL("path/to/git/repo").normalizedURLString) == expected
					}

					do {
						let expected = "./path/to/git/repo"
						expect(GitURL("./path/to/git/repo.git").normalizedURLString) == expected
						expect(GitURL("./path/to/git/repo").normalizedURLString) == expected
					}

					do {
						let expected = "../path/to/git/repo"
						expect(GitURL("../path/to/git/repo.git").normalizedURLString) == expected
						expect(GitURL("../path/to/git/repo").normalizedURLString) == expected
					}

					do {
						let expected = "~/path/to/git/repo"
						expect(GitURL("~/path/to/git/repo.git").normalizedURLString) == expected
						expect(GitURL("~/path/to/git/repo").normalizedURLString) == expected
					}
				}

				it("should parse scp syntax") {
					let expected = "github.com/antitypical/Result"
					expect(GitURL("git@github.com:antitypical/Result.git").normalizedURLString) == expected
					expect(GitURL("github.com:antitypical/Result").normalizedURLString) == expected
				}
			}
		}
	}
}
