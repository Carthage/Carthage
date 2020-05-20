import Foundation

struct Proxy {
	let connectionProxyDictionary: [AnyHashable: Any]?

	init(environment: [String: String]) {
		let http = Proxy.makeHTTPDictionary(environment)
		let https = Proxy.makeHTTPSDictionary(environment)
        let noProxy = Proxy.makeNoProxyDictionary(environment)

        let combined = http.merging(https) { _, property in property }.merging(noProxy) { _, property in property }

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
    
    private static func makeNoProxyDictionary(_ environment: [String: String]) -> [AnyHashable: Any] {
        #if os(OSX)
        
        let vars = ["no_proxy", "NO_PROXY"]
        guard
            let noProxyList: [String] = (vars.compactMap { environment[$0] }.first)?.split(separator: ",").compactMap({ String($0) }),
            !noProxyList.isEmpty
            else { return [:] }
        
        let dictionary: [AnyHashable: Any] = [
            kCFNetworkProxiesExceptionsList: noProxyList
        ]
        
        return dictionary
        
        #else
        return [:]
        #endif
    }

}

extension Proxy {
	static let `default`: Proxy = Proxy(environment: ProcessInfo.processInfo.environment)
}

extension URLSession {
    public static var proxiedSession: URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.connectionProxyDictionary = Proxy.default.connectionProxyDictionary

        return URLSession(configuration: configuration)
    }
}
