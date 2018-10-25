import Foundation

struct Proxy {
	let connectionProxyDictionary: [AnyHashable: Any]?

	init(environment: [String: String]) {
		let http = Proxy.makeHTTPDictionary(environment)
		let https = Proxy.makeHTTPSDictionary(environment)

		let combined = http.merging(https) { _, property in property }

		// the proxy dictionary on URLSessionConfiguration must be nil so that it can default to the system proxy.
		connectionProxyDictionary = combined.isEmpty ? nil : combined
	}

	private static func makeHTTPDictionary(_ environment: [String: String]) -> [AnyHashable: Any] {
		let vars = ["http_proxy", "HTTP_PROXY"]
		guard let proxyURL = URL(string: vars.compactMap { environment[$0] }.first ?? "") else {
			return [:]
		}

		var dictionary: [AnyHashable: Any] = [:]
		dictionary[kCFNetworkProxiesHTTPEnable] = true
		dictionary[kCFNetworkProxiesHTTPProxy] = proxyURL.host

		if let port = proxyURL.port {
			dictionary[kCFNetworkProxiesHTTPPort] = port
		}

		return dictionary
	}

	private static func makeHTTPSDictionary(_ environment: [String: String]) -> [AnyHashable: Any] {
		let vars = ["https_proxy", "HTTPS_PROXY"]
		guard let proxyURL = URL(string: vars.compactMap { environment[$0] }.first ?? "") else {
			return [:]
		}

		var dictionary: [AnyHashable: Any] = [:]
		dictionary[kCFNetworkProxiesHTTPSEnable] = true
		dictionary[kCFNetworkProxiesHTTPSProxy] = proxyURL.host

		if let port = proxyURL.port {
			dictionary[kCFNetworkProxiesHTTPSPort] = port
		}

		return dictionary
	}
}

extension Proxy {
	static let `default`: Proxy = Proxy(environment: ProcessInfo.processInfo.environment)
}
