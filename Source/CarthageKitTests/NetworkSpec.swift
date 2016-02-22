import Quick
import Nimble
import ReactiveCocoa
import CarthageKit

class NetworkSpec: QuickSpec {
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

		describe("executeDataRequest") {
			var producer: SignalProducer<NSURL, CarthageError>!
			var events: [Event<NSURL, CarthageError>] = []

			let urlRequest = createURLRequest(NSURL(string: "https://example.com")!)

			beforeEach {
				events = []
				producer = executeDownloadRequest(urlRequest)
				producer.on(event: { event in
					events.append(event)
				}).start()
			}

			it("makes a data request to an NSURLSession") {
				fail("How do we test that rac_dataTaskWithRequest was called? I'd rather not have to rely on that particular implementation detail")
			}

			context("when the download succeeds") {
				it("returns a local URL for the file downloaded") {
					expect(events.count) == 2
					expect(events[0].error).to(beNil())
					expect(events[0].value).toNot(beNil())
					expect(events[1] == Event.Completed) == true
				}
			}

			context("when the download fails") {
				it("returns a network error") {
					let error = NSError(domain: "Some domain", code: 666, userInfo: nil)

					expect(events.count) == 1
					expect(events[0].value).to(beNil())
					expect(events[0].error) == CarthageError.NetworkError(error)
				}
			}
		}

		describe("executeDownloadRequest") {
			var producer: SignalProducer<NSURL, CarthageError>!
			var events: [Event<NSURL, CarthageError>] = []

			let urlRequest = createURLRequest(NSURL(string: "https://example.com")!)

			beforeEach {
				events = []
				producer = executeDownloadRequest(urlRequest)
				producer.on(event: { event in
					events.append(event)
				}).start()
			}

			it("makes a download request to an NSURLSession") {
				fail("Mock out the network so I can be tested!")
			}

			context("when the download succeeds") {
				it("returns a local URL for the file downloaded") {
					expect(events.count) == 2
					expect(events[0].error).to(beNil())
					expect(events[0].value?.fileURL) == true
					expect(events[1] == Event.Completed) == true
				}
			}

			context("when the download fails") {
				it("returns a network error") {
					let error = NSError(domain: "Some domain", code: 666, userInfo: nil)

					expect(events.count) == 1
					expect(events[0].value).to(beNil())
					expect(events[0].error) == CarthageError.NetworkError(error)
				}
			}
		}
	}
}