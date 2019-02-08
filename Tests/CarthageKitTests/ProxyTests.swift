@testable import CarthageKit
import Foundation
import Nimble
import Quick

class ProxySpec: QuickSpec {
	override func spec() {
		describe("createProxyWithNoProxyValues") {
			let proxy = Proxy(environment: [:])

			it("should have nil dictionary") {
				expect(proxy.connectionProxyDictionary).to(beNil())
			}
		}

		describe("createProxyWithMalformedProxyValues") {
			let proxy = Proxy(environment: ["http_proxy": "http:\\github.com:8888"])

			it("should have nil dictionary") {
				expect(proxy.connectionProxyDictionary).to(beNil())
			}
		}

		describe("createProxyWithHTTPValues") {
			let proxy = Proxy(environment: ["http_proxy": "http://github.com:8888", "HTTP_PROXY": "http://github.com:8888"])

			it("should set the http properties") {
				expect(proxy.connectionProxyDictionary).toNot(beNil())
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPEnable] as? Bool).to(beTrue())
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPProxy] as? String) == URL(string: "http://github.com:8888")?.host
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPPort] as? Int) == 8888
			}

			it("should not set the https properties") {
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPSEnable]).to(beNil())
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPSProxy]).to(beNil())
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPSPort]).to(beNil())
			}
		}

		describe("createProxyWithHTTPSValues") {
			let proxy = Proxy(environment: ["https_proxy": "https://github.com:8888", "HTTPS_PROXY": "https://github.com:8888"])

			it("should set the https properties") {
				expect(proxy.connectionProxyDictionary).toNot(beNil())
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPSEnable] as? Bool).to(beTrue())
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPSProxy] as? String) == URL(string: "https://github.com:8888")?.host
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPSPort] as? Int) == 8888
			}

			it("should not set the http properties") {
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPEnable]).to(beNil())
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPProxy]).to(beNil())
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPPort]).to(beNil())
			}
		}

		describe("createProxyWithHTTPAndHTTPSValues") {
			let proxy = Proxy(environment: [
				"http_proxy": "http://github.com:8888",
				"HTTP_PROXY": "http://github.com:8888",
				"https_proxy": "https://github.com:443",
				"HTTPS_PROXY": "https://github.com:443",
				])

			it("should set the http properties") {
				expect(proxy.connectionProxyDictionary).toNot(beNil())
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPEnable] as? Bool).to(beTrue())
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPProxy] as? String) == URL(string: "http://github.com:8888")?.host
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPPort] as? Int) == 8888
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPSEnable] as? Bool).to(beTrue())
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPSProxy] as? String) == URL(string: "https://github.com:443")?.host
				expect(proxy.connectionProxyDictionary?[kCFNetworkProxiesHTTPSPort] as? Int) == 443
			}
		}
	}
}
