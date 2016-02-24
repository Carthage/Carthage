import Quick
import Nimble
import ReactiveCocoa
import CarthageKit

class NetworkClientSpec: QuickSpec {
	override func spec() {
		describe("createURLRequest") {
			let url = NSURL(string: "https://example.com")!

			it("creates an NSURLRequest with the given url") {
				let urlRequest = createURLRequest(url)

				expect(urlRequest.URL) == url
				expect(urlRequest.allHTTPHeaderFields) == [:]
			}

			it("uses the given headers if specified") {
				let urlRequest = createURLRequest(url, ["exampleHeader": "exampleValue"])

				expect(urlRequest.allHTTPHeaderFields) == ["exampleHeader": "exampleValue"]
			}
		}

		describe("URLSessionNetworkClient") {
			var subject: URLSessionNetworkClient!
			var urlSession: FakeURLSession!

			let urlRequest = createURLRequest(NSURL(string: "https://example.com")!)

			beforeEach {
				urlSession = FakeURLSession()
				subject = URLSessionNetworkClient(urlSession: urlSession)
			}

			describe("executeDataRequest") {
				var producer: SignalProducer<NSData, CarthageError>!
				var events: [Event<NSData, CarthageError>] = []

				beforeEach {
					events = []
					producer = subject.executeDataRequest(urlRequest)
					producer.on(event: { event in
						events.append(event)
					}).start()
				}

				it("makes a data request to an NSURLSession") {
					expect(urlSession.dataTaskWithRequestArgs.count) == 1
					let (request, _, task) = urlSession.dataTaskWithRequestArgs[0]

					expect(task.started) == true
					expect(request) == urlRequest
				}

				context("when the download succeeds") {
					it("returns the data for the file downloaded") {
						let data = "Example response".dataUsingEncoding(NSUTF8StringEncoding)!
						let (request, completion, _) = urlSession.dataTaskWithRequestArgs[0]
						let response = NSHTTPURLResponse(URL: request.URL!, statusCode: 200, HTTPVersion: nil, headerFields: nil)
						completion(data, response, nil)

						expect(events.count) == 2
						expect(events[0].error).to(beNil())
						expect(events[0].value) == data
						expect(events[1] == Event.Completed) == true
					}
				}

				context("when the download fails") {
					it("returns a network error") {
						let (request, completion, _) = urlSession.dataTaskWithRequestArgs[0]

						let response = NSHTTPURLResponse(URL: request.URL!, statusCode: 401, HTTPVersion: nil, headerFields: nil)
						let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)
						completion(nil, response, error)

						expect(events.count) == 1
						expect(events[0].value).to(beNil())
						expect(events[0].error) == CarthageError.NetworkError(error)
					}
				}
			}

			describe("executeDownloadRequest") {
				var producer: SignalProducer<NSURL, CarthageError>!
				var events: [Event<NSURL, CarthageError>] = []

				beforeEach {
					events = []
					producer = subject.executeDownloadRequest(urlRequest)
					producer.on(event: { event in
						events.append(event)
					}).start()
				}

				it("makes a download request to an NSURLSession") {
					expect(urlSession.downloadTaskWithRequestArgs.count) == 1
					let (request, _, task) = urlSession.downloadTaskWithRequestArgs[0]

					expect(task.started) == true
					expect(request) == urlRequest
				}

				context("when the download succeeds") {
					it("returns a local URL for the file downloaded") {
						let (request, completion, _) = urlSession.downloadTaskWithRequestArgs[0]

						let response = NSHTTPURLResponse(URL: request.URL!, statusCode: 404, HTTPVersion: nil, headerFields: nil)
						let downloadedURL = NSURL(string: "file:///Foo/Bar/file")!

						completion(downloadedURL, response, nil)

						expect(events.count) == 2
						expect(events[0].error).to(beNil())
						expect(events[0].value?.fileURL) == true
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
}