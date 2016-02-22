import ReactiveCocoa

public func createURLRequest(URL: NSURL, _ headers: [String: String] = [:]) -> NSURLRequest {
	let urlRequest = NSMutableURLRequest(URL: URL)
	urlRequest.allHTTPHeaderFields = headers
	return urlRequest
}

public func executeDataRequest(request: NSURLRequest) -> SignalProducer<NSData, CarthageError> {
	return SignalProducer(values: [])
}

public func executeDownloadRequest(request: NSURLRequest) -> SignalProducer<NSURL, CarthageError> {
	return SignalProducer(values: [])
}
