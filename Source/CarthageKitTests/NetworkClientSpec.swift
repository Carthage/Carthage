import Quick
import Nimble
import ReactiveCocoa
import CarthageKit
import OHHTTPStubs

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
			let urlRequest = createURLRequest(NSURL(string: "https://example.com")!)

			var subject: URLSessionNetworkClient!
			var urlSession: NSURLSession!

			var receivedRequest: NSURLRequest?

			beforeEach {
				urlSession = NSURLSession(configuration: NSURLSessionConfiguration.ephemeralSessionConfiguration())
				subject = URLSessionNetworkClient(urlSession: urlSession)
			}

			afterEach {
				OHHTTPStubs.removeAllStubs()
			}

			func makeRequest(response: OHHTTPStubsResponse, request requestBlock: NSURLRequest -> Void) {
				stub(isHost(urlRequest.URL!.host!)) { request in
					receivedRequest = request
					return response
				}

				requestBlock(urlRequest)
			}

			describe("executeDataRequest") {
				var producer: SignalProducer<NSData, CarthageError>!
				var events: [Event<NSData, CarthageError>] = []

				func requestFunction(request: NSURLRequest) {
					events = []
					producer = subject.executeDataRequest(urlRequest)
					_ = producer.on(event: { event in
						events.append(event)
					}).wait()
				}

				it("makes a data request to an NSURLSession") {
					let response = OHHTTPStubsResponse(JSONObject: [:], statusCode: 200, headers: nil)
					makeRequest(response, request: requestFunction)

					expect(receivedRequest) == urlRequest
				}

				context("when the download succeeds") {
					it("returns the data for the file downloaded") {
						let data = "Example response".dataUsingEncoding(NSUTF8StringEncoding)!
						let response = OHHTTPStubsResponse(data: data, statusCode: 200, headers: nil)
						makeRequest(response, request: requestFunction)

						expect(events.count) == 2
						expect(events[0].error).to(beNil())
						expect(events[0].value) == data
						expect(events[1] == Event.Completed) == true
					}
				}

				context("when the download fails") {
					it("returns a network error") {
						let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)

						let response = OHHTTPStubsResponse(error: error)
						makeRequest(response, request: requestFunction)

						expect(events.count) == 1
						expect(events[0].value).to(beNil())
						expect(events[0].error) == CarthageError.NetworkError(error)
					}
				}
			}

			describe("executeDownloadRequest") {
				var producer: SignalProducer<NSURL, CarthageError>!
				var events: [Event<NSURL, CarthageError>] = []

				func requestFunction(request: NSURLRequest) {
					events = []
					producer = subject.executeDownloadRequest(request)
					_ = producer.on(event: { event in
						events.append(event)
					}).wait()
				}

				it("makes a download request to an NSURLSession") {
					let response = OHHTTPStubsResponse(JSONObject: [:], statusCode: 200, headers: nil)
					makeRequest(response, request: requestFunction)

					expect(receivedRequest) == urlRequest
				}

				context("when the download succeeds") {
					it("returns a local URL for the file downloaded") {
						let data = "Hello world".dataUsingEncoding(NSUTF8StringEncoding)!
						let response = OHHTTPStubsResponse(data: data, statusCode: 200, headers: nil)
						makeRequest(response, request: requestFunction)

						expect(events.count) == 2
						expect(events[0].error).to(beNil())
						expect(events[0].value?.fileURL) == true

						let fileData = NSData(contentsOfURL: events[0].value!)
						expect(fileData) == data

						expect(events[1] == Event.Completed) == true
					}
				}

				context("when the download fails") {
					it("returns a network error") {
						let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)

						let response = OHHTTPStubsResponse(error: error)
						makeRequest(response, request: requestFunction)

						expect(events.count) == 1
						expect(events[0].value).to(beNil())
						expect(events[0].error) == CarthageError.NetworkError(error)
					}
				}
			}
		}
	}
}