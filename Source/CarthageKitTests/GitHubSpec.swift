import Quick
import Nimble
import Result
import ReactiveCocoa
import CarthageKit

class GitHubSpec: QuickSpec {
	override func spec() {
		describe("releaseForTag:repository:authorizationHeaderValue:urlSession:") {
			it("makes a request to the specified server") {
				let gitHubEnterpriseRepository = GitHubRepository(server: GitHubRepository.Server.Enterprise(scheme: "https", hostname: "example.com"), owner: "Carthage", name: "Carthage")

				let networkClient = FakeNetworkClient()

				_ = releaseForTag("v1.0.0", gitHubEnterpriseRepository, "example", networkClient).start()

				expect(networkClient.executeDataRequestCallCount) == 1
				let request = networkClient.executeDataRequestArgsForCall(0)

				expect(request.URL) == NSURL(string: "https://example.com/api/v3/repos/Carthage/Carthage/releases/tags/v1.0.0")
				expect(request.valueForHTTPHeaderField("Accept")) == "application/vnd.github.v3+json"
				expect(request.valueForHTTPHeaderField("User-Agent")) == "CarthageKit-unknown/unknown"
				expect(request.valueForHTTPHeaderField("Authorization")) == "example"
			}

			describe("for a standard github repo") {
				let gitHubRepository = GitHubRepository(owner: "Example", name: "Carthage")

				var releaseProducer: SignalProducer<GitHubRelease, CarthageError>!
				var networkClient: FakeNetworkClient!
				var events: [Event<GitHubRelease, CarthageError>] = []

				beforeEach {
					networkClient = FakeNetworkClient()
					releaseProducer = releaseForTag("v1.0.0", gitHubRepository, "example", networkClient)

					events = []
					releaseProducer.on(event: { event in
						events.append(event)
					}).start()
				}

				it("makes a request to github") {
					expect(networkClient.executeDataRequestCallCount) == 1
					let request = networkClient.executeDataRequestArgsForCall(0)

					expect(request.URL) == NSURL(string: "https://api.github.com/repos/Example/Carthage/releases/tags/v1.0.0")
					expect(request.valueForHTTPHeaderField("Accept")) == "application/vnd.github.v3+json"
					expect(request.valueForHTTPHeaderField("User-Agent")) == "CarthageKit-unknown/unknown"
					expect(request.valueForHTTPHeaderField("Authorization")) == "example"
				}

				context("when the request succeeds") {
					it("returns a GitHubRelease object when given a valid GitHubRelease dictionary data") {
						let observer = networkClient.executeDataRequestObserverForCall(0)

						let responseDictionary = [
							"id": 1,
							"name": "example release",
							"tag_name": "v1.0.0",
							"draft": false,
							"prerelease": false,
							"assets": [
								[
									"id": 2,
									"name": "example asset",
									"content_type": "text/text",
									"url": "https://example.com/asset"
								]
							]
						]
						let data = try! NSJSONSerialization.dataWithJSONObject(responseDictionary, options: [])
						observer.sendNext(data)
						observer.sendCompleted()

						let asset = GitHubRelease.Asset(ID: 2, name: "example asset", contentType: "text/text", URL: NSURL(string: "https://example.com/asset")!)
						let release = GitHubRelease(ID: 1, name: "example release", tag: "v1.0.0", draft: false, prerelease: false, assets: [asset])

						expect(events.count) == 2
						expect(events[0].error).to(beNil())
						expect(events[0].value) == release
						expect(events[1] == Event.Completed) == true
					}

					it("returns nothing when given a valid json object, but not decodeable to a GitHubRelease object") {
						let observer = networkClient.executeDataRequestObserverForCall(0)

						let data = "{}".dataUsingEncoding(NSUTF8StringEncoding)!
						observer.sendNext(data)
						observer.sendCompleted()

						expect(events.count) == 1
						expect(events[0] == Event.Completed) == true
					}

					it("returns an error when not given a valid json object") {
						let observer = networkClient.executeDataRequestObserverForCall(0)

						let data = "example string".dataUsingEncoding(NSUTF8StringEncoding)!
						observer.sendNext(data)
						observer.sendCompleted()

						expect(events.count) == 1
						expect(events[0].value).to(beNil())
						expect(events[0].error) == CarthageError.ParseError(description: "Invalid JSON in releases for tag v1.0.0")
					}
				}

				context("when the request fails") {
					it("forwards the error") {
						let observer = networkClient.executeDataRequestObserverForCall(0)

						let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)
						observer.sendFailed(CarthageError.NetworkError(error))

						expect(events.count) == 1
						expect(events[0].value).to(beNil())
						expect(events[0].error) == CarthageError.NetworkError(error)
					}
				}
			}
		}

		describe("downloadAsset:authorizationHeaderValue:urlSession:") {
			// basically, the only special thing it does is create the request data
			var releaseProducer: SignalProducer<NSURL, CarthageError>!
			var networkClient: FakeNetworkClient!
			var events: [Event<NSURL, CarthageError>] = []

			let URL = NSURL(string: "https://example.com/asset")!

			beforeEach {
				networkClient = FakeNetworkClient()
				let asset = GitHubRelease.Asset(ID: 0, name: "example", contentType: "text/text", URL: URL)
				releaseProducer = downloadAsset(asset, "example", networkClient)

				events = []
				releaseProducer.on(event: { event in
					events.append(event)
				}).start()
			}

			it("makes a download request to the url") {
				expect(networkClient.executeDownloadRequestCallCount) == 1
				let request = networkClient.executeDownloadRequestArgsForCall(0)

				expect(request.URL) == URL
				expect(request.valueForHTTPHeaderField("Accept")) == "application/octet-stream"
				expect(request.valueForHTTPHeaderField("User-Agent")) == "CarthageKit-unknown/unknown"
				expect(request.valueForHTTPHeaderField("Authorization")) == "example"
			}

			context("when the download succeeds") {
				it("successfully returns a local URL that was downloaded") {
					let observer = networkClient.executeDownloadRequestObserverForCall(0)

					let downloadedURL = NSURL(string: "file:///Foo/Bar/file")!
					observer.sendNext(downloadedURL)
					observer.sendCompleted()

					expect(events.count) == 2
					expect(events[0].error).to(beNil())
					expect(events[0].value) == downloadedURL
					expect(events[1] == Event.Completed) == true
				}
			}

			context("when the download fails") {
				it("returns a network error") {
					let observer = networkClient.executeDownloadRequestObserverForCall(0)

					let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)
					observer.sendFailed(CarthageError.NetworkError(error))

					expect(events.count) == 1
					expect(events[0].value).to(beNil())
					expect(events[0].error) == CarthageError.NetworkError(error)
				}
			}
		}
	}
}