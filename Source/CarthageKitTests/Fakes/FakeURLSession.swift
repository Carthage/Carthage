import Foundation

final class FakeDownloadTask: NSURLSessionDownloadTask {
	var started = false
	override func resume() {
		self.started = true
	}

	var cancelled = false
	override func cancel() {
		self.cancelled = true
	}
}

final class FakeDataTask: NSURLSessionDataTask {
	var started = false
	override func resume() {
		self.started = true
	}

	var cancelled = false
	override func cancel() {
		self.cancelled = true
	}
}

final class FakeURLSession: NSURLSession {
	var downloadTaskWithRequestArgs: [(NSURLRequest, (NSURL?, NSURLResponse?, NSError?) -> Void, FakeDownloadTask)] = []
	override func downloadTaskWithRequest(request: NSURLRequest, completionHandler: (NSURL?, NSURLResponse?, NSError?) -> Void) -> NSURLSessionDownloadTask {
		let downloadTask = FakeDownloadTask()
		self.downloadTaskWithRequestArgs.append((request, completionHandler, downloadTask))
		return downloadTask
	}

	var dataTaskWithRequestArgs: [(NSURLRequest, (NSData?, NSURLResponse?, NSError?) -> Void, FakeDataTask)] = []
	override func dataTaskWithRequest(request: NSURLRequest, completionHandler: (NSData?, NSURLResponse?, NSError?) -> Void) -> NSURLSessionDataTask {
		let dataTask = FakeDataTask()
		dataTaskWithRequestArgs.append((request, completionHandler, dataTask))
		return dataTask
	}
}