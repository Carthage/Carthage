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

				let urlSession = FakeURLSession()
				_ = releaseForTag("v1.0.0", gitHubEnterpriseRepository, "example", urlSession).start()

				expect(urlSession.dataTaskWithRequestArgs.count) == 1
				let (request, _, task) = urlSession.dataTaskWithRequestArgs[0]

				expect(task.started) == true
				expect(request.URL) == NSURL(string: "https://example.com/api/v3/repos/Carthage/Carthage/releases/tags/v1.0.0")
				expect(request.valueForHTTPHeaderField("Accept")) == "application/vnd.github.v3+json"
				expect(request.valueForHTTPHeaderField("User-Agent")) == "CarthageKit-unknown/unknown"
				expect(request.valueForHTTPHeaderField("Authorization")) == "example"
			}

			describe("for a standard github repo") {
				let gitHubRepository = GitHubRepository(owner: "Example", name: "Carthage")

				var releaseProducer: SignalProducer<GitHubRelease, CarthageError>!
				var urlSession: FakeURLSession!
				var events: [Event<GitHubRelease, CarthageError>] = []

				beforeEach {
					urlSession = FakeURLSession()
					releaseProducer = releaseForTag("v1.0.0", gitHubRepository, "example", urlSession)

					events = []
					releaseProducer.on(event: { event in
						events.append(event)
					}).start()
				}

				it("makes a request to github") {
					expect(urlSession.dataTaskWithRequestArgs.count) == 1
					let (request, _, task) = urlSession.dataTaskWithRequestArgs[0]

					expect(task.started) == true
					expect(request.URL) == NSURL(string: "https://api.github.com/repos/Example/Carthage/releases/tags/v1.0.0")
					expect(request.valueForHTTPHeaderField("Accept")) == "application/vnd.github.v3+json"
					expect(request.valueForHTTPHeaderField("User-Agent")) == "CarthageKit-unknown/unknown"
					expect(request.valueForHTTPHeaderField("Authorization")) == "example"
				}

				context("when the request succeeds") {
					it("returns a GitHubRelease object when given a valid GitHubRelease dictionary data") {
						let (request, completion, _) = urlSession.dataTaskWithRequestArgs[0]

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
						let data = try? NSJSONSerialization.dataWithJSONObject(responseDictionary, options: [])
						let response = NSHTTPURLResponse(URL: request.URL!, statusCode: 200, HTTPVersion: nil, headerFields: nil)
						completion(data, response, nil)

						let asset = GitHubRelease.Asset(ID: 2, name: "example asset", contentType: "text/text", URL: NSURL(string: "https://example.com/asset")!)
						let release = GitHubRelease(ID: 1, name: "example release", tag: "v1.0.0", draft: false, prerelease: false, assets: [asset])

						expect(events.count) == 2
						expect(events[0].error).to(beNil())
						expect(events[0].value) == release
						expect(events[1] == Event.Completed) == true
					}

					it("returns nothing when given a valid json object, but not decodeable to a GitHubRelease object") {
						let (request, completion, _) = urlSession.dataTaskWithRequestArgs[0]

						let data = "{}".dataUsingEncoding(NSUTF8StringEncoding)
						let response = NSHTTPURLResponse(URL: request.URL!, statusCode: 200, HTTPVersion: nil, headerFields: nil)
						completion(data, response, nil)

						expect(events.count) == 1
						expect(events[0] == Event.Completed) == true
					}

					it("returns an error when not given a valid json object") {
						let (request, completion, _) = urlSession.dataTaskWithRequestArgs[0]

						let data = "example string".dataUsingEncoding(NSUTF8StringEncoding)
						let response = NSHTTPURLResponse(URL: request.URL!, statusCode: 200, HTTPVersion: nil, headerFields: nil)
						completion(data, response, nil)

						expect(events.count) == 1
						expect(events[0].value).to(beNil())
						expect(events[0].error) == CarthageError.ParseError(description: "Invalid JSON in releases for tag v1.0.0")
					}
				}

				context("when the request fails") {
					context("with a 400 or 500 level error that is not a 404") {
						it("returns a parse error if it cannot parse the error message json") {
							let (request, completion, _) = urlSession.dataTaskWithRequestArgs[0]

							let data = "example string".dataUsingEncoding(NSUTF8StringEncoding)
							let response = NSHTTPURLResponse(URL: request.URL!, statusCode: 401, HTTPVersion: nil, headerFields: nil)
							let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)
							completion(data, response, error)

							expect(events.count) == 1
							expect(events[0].value).to(beNil())
							expect(events[0].error) == CarthageError.GitHubAPIRequestFailed("Parse error: Invalid JSON in API error response 'example string'")
						}

						it("returns a network error when not given a data object") {
							let (request, completion, _) = urlSession.dataTaskWithRequestArgs[0]

							let response = NSHTTPURLResponse(URL: request.URL!, statusCode: 401, HTTPVersion: nil, headerFields: nil)
							let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)
							completion(nil, response, error)

							expect(events.count) == 1
							expect(events[0].value).to(beNil())
							expect(events[0].error) == CarthageError.NetworkError(error)
						}
					}

					context("with a 404 error") {
						it("returns a network error") {
							let (request, completion, _) = urlSession.dataTaskWithRequestArgs[0]

							let response = NSHTTPURLResponse(URL: request.URL!, statusCode: 404, HTTPVersion: nil, headerFields: nil)
							let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)
							completion(nil, response, error)

							expect(events.count) == 1
							expect(events[0].value).to(beNil())
							expect(events[0].error) == CarthageError.NetworkError(error)
						}
					}
				}
			}
		}

		describe("downloadAsset:authorizationHeaderValue:urlSession:") {
			var releaseProducer: SignalProducer<NSURL, CarthageError>!
			var urlSession: FakeURLSession!
			var events: [Event<NSURL, CarthageError>] = []

			let URL = NSURL(string: "https://example.com/asset")!

			beforeEach {
				urlSession = FakeURLSession()
				let asset = GitHubRelease.Asset(ID: 0, name: "example", contentType: "text/text", URL: URL)
				releaseProducer = downloadAsset(asset, "example", urlSession)

				events = []
				releaseProducer.on(event: { event in
					events.append(event)
				}).start()
			}

			it("makes a download request to the url") {
				expect(urlSession.downloadTaskWithRequestArgs.count) == 1
				let (request, _, task) = urlSession.downloadTaskWithRequestArgs[0]

				expect(task.started) == true
				expect(request.URL) == URL
				expect(request.valueForHTTPHeaderField("Accept")) == "application/octet-stream"
				expect(request.valueForHTTPHeaderField("User-Agent")) == "CarthageKit-unknown/unknown"
				expect(request.valueForHTTPHeaderField("Authorization")) == "example"
			}

			context("when the download succeeds") {
				it("successfully returns a local URL that was downloaded") {
					let (request, completion, _) = urlSession.downloadTaskWithRequestArgs[0]

					let response = NSHTTPURLResponse(URL: request.URL!, statusCode: 404, HTTPVersion: nil, headerFields: nil)
					let downloadedURL = NSURL(string: "file:///Foo/Bar/file")!

					completion(downloadedURL, response, nil)

					expect(events.count) == 2
					expect(events[0].error).to(beNil())
					expect(events[0].value) == downloadedURL
					expect(events[1] == Event.Completed) == true
				}
			}

			context("when the download fails") {
				it("returns a network error") {
					let (request, completion, _) = urlSession.downloadTaskWithRequestArgs[0]

					let response = NSHTTPURLResponse(URL: request.URL!, statusCode: 404, HTTPVersion: nil, headerFields: nil)
					let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)
					completion(nil, response, error)

					expect(events.count) == 1
					expect(events[0].value).to(beNil())
					expect(events[0].error) == CarthageError.NetworkError(error)
				}
			}
		}
	}
}