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
		
		describe("Redirection") {
			let subject = GitHubURLSessionDelegate()
			let session = URLSession(configuration: .default)
			let requestURL = URL(string: "https://api.github.com/some_api_endpoint")!
			let insideGitHubRedirectURL = URL(string: "https://api.github.com/some_redirected_api_endpoint")!
			let outsideGitHubRedirectURL = URL(string: "https://api.notgithub.com/")!
			var request = URLRequest(url: requestURL)
			let authToken = "TOKEN"
			request.setValue(authToken, forHTTPHeaderField: "Authorization")
			let task = session.dataTask(with: request)
			
			func redirectURLResponse(location: URL) -> HTTPURLResponse {
				return HTTPURLResponse(url: requestURL, statusCode: 302, httpVersion: "1.1", headerFields: [
					"Location": location.absoluteString
					])!
			}
			
			describe("within github.com") {
				it("should forward the Authorization header") {
					let response = redirectURLResponse(location: insideGitHubRedirectURL)
					let newRequest = URLRequest(url: insideGitHubRedirectURL)
					
					subject.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: newRequest, completionHandler: { redirectedRequest in
						expect(redirectedRequest?.value(forHTTPHeaderField: "Authorization")) == authToken
					})
				}
			}
			
			describe("away from github.com") {
				it("should not forward the Authorization header") {
					let response = redirectURLResponse(location: outsideGitHubRedirectURL)
					let newRequest = URLRequest(url: outsideGitHubRedirectURL)
					
					subject.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: newRequest, completionHandler: { redirectedRequest in
						expect(redirectedRequest?.value(forHTTPHeaderField: "Authorization")).to(beNil())
					})
				}
			}
		}
	}
}
