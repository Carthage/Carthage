import ReactiveCocoa


public func createURLRequest(URL: NSURL, _ headers: [String: String] = [:]) -> NSURLRequest {
	let urlRequest = NSMutableURLRequest(URL: URL)
	urlRequest.allHTTPHeaderFields = headers
	return urlRequest
}

public protocol NetworkClient {
	func executeDataRequest(request: NSURLRequest) -> SignalProducer<NSData, CarthageError>
	func executeDownloadRequest(request: NSURLRequest) -> SignalProducer<NSURL, CarthageError>
}

private let defaultSessionError = NSError(domain: "org.carthage.CarthageKit.carthage_downloadWithRequest", code: 1, userInfo: nil)

public struct URLSessionNetworkClient: NetworkClient {
	private let urlSession: NSURLSession
	public init(urlSession: NSURLSession) {
		self.urlSession = urlSession
	}

	public func executeDataRequest(request: NSURLRequest) -> SignalProducer<NSData, CarthageError> {
		return self.urlSession.rac_dataWithRequest(request)
			.mapError(CarthageError.NetworkError)
			.flatMap(.Concat) { data, _ in SignalProducer(value: data) }
	}

	public func executeDownloadRequest(request: NSURLRequest) -> SignalProducer<NSURL, CarthageError> {
		return SignalProducer { observer, disposable in
			let serialDisposable = SerialDisposable()
			let handle = disposable.addDisposable(serialDisposable)

			let task = self.urlSession.downloadTaskWithRequest(request) { (URL, response, error) in
				// Avoid invoking cancel(), or the download may be deleted.
				handle.remove()

				if let URL = URL, _ = response {
					observer.sendNext(URL)
					observer.sendCompleted()
				} else {
					let carthageError = CarthageError.NetworkError(error ?? defaultSessionError)
					observer.sendFailed(carthageError)
				}
			}

			serialDisposable.innerDisposable = ActionDisposable {
				task.cancel()
			}

			task.resume()
		}
	}
}
