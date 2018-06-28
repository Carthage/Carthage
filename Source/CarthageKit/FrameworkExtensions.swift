import Foundation
import Result
import ReactiveSwift

extension String {
	/// Returns a producer that will enumerate each line of the receiver, then
	/// complete.
	internal var linesProducer: SignalProducer<String, NoError> {
		return SignalProducer { observer, lifetime in
			self.enumerateLines { line, stop in
				observer.send(value: line)

				if lifetime.hasEnded {
					stop = true
				}
			}

			observer.sendCompleted()
		}
	}

	/// Strips off a prefix string, if present.
	internal func stripping(prefix: String) -> String {
		guard hasPrefix(prefix) else { return self }
		return String(self.dropFirst(prefix.count))
	}

	/// Strips off a trailing string, if present.
	internal func stripping(suffix: String) -> String {
		if hasSuffix(suffix) {
			let end = index(endIndex, offsetBy: -suffix.count)
			return String(self[startIndex..<end])
		} else {
			return self
		}
	}
}

extension Signal {
	/// Sends each value that occurs on `signal` combined with each value that
	/// occurs on `otherSignal` (repeats included).
	fileprivate func permute<U>(with otherSignal: Signal<U, Error>) -> Signal<(Value, U), Error> {
		// swiftlint:disable:previous cyclomatic_complexity function_body_length
		return Signal<(Value, U), Error> { observer, lifetime in
			let lock = NSLock()
			lock.name = "org.carthage.CarthageKit.permute"

			var signalValues: [Value] = []
			var signalCompleted = false
			var otherValues: [U] = []
			var otherCompleted = false

			let compositeDisposable = CompositeDisposable()
			lifetime += compositeDisposable

			compositeDisposable += self.observe { event in
				switch event {
				case let .value(value):
					lock.lock()

					signalValues.append(value)
					for otherValue in otherValues {
						observer.send(value: (value, otherValue))
					}

					lock.unlock()

				case let .failed(error):
					observer.send(error: error)

				case .completed:
					lock.lock()

					signalCompleted = true
					if otherCompleted {
						observer.sendCompleted()
					}

					lock.unlock()

				case .interrupted:
					observer.sendInterrupted()
				}
			}

			compositeDisposable += otherSignal.observe { event in
				switch event {
				case let .value(value):
					lock.lock()

					otherValues.append(value)
					for signalValue in signalValues {
						observer.send(value: (signalValue, value))
					}

					lock.unlock()

				case let .failed(error):
					observer.send(error: error)

				case .completed:
					lock.lock()

					otherCompleted = true
					if signalCompleted {
						observer.sendCompleted()
					}

					lock.unlock()

				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}
}

extension SignalProducer {
	/// Sends each value that occurs on `producer` combined with each value that
	/// occurs on `otherProducer` (repeats included).
	fileprivate func permute<U>(with otherProducer: SignalProducer<U, Error>) -> SignalProducer<(Value, U), Error> {
		return lift(Signal.permute(with:))(otherProducer)
	}

	/// Sends a boolean of whether the producer succeeded or failed.
	internal func succeeded() -> SignalProducer<Bool, NoError> {
		return self
			.then(SignalProducer<Bool, Error>(value: true))
			.flatMapError { _ in .init(value: false) }
	}
}

extension SignalProducer where Value: SignalProducerProtocol, Error == Value.Error {
	/// Sends all permutations of the values from the inner producers, as they arrive.
	///
	/// If no producers are received, sends a single empty array then completes.
	internal func permute() -> SignalProducer<[Value.Value], Error> {
		return self
			.collect()
			.flatMap(.concat) { (producers: [Value]) -> SignalProducer<[Value.Value], Error> in
				var combined = SignalProducer<[Value.Value], Error>(value: [])

				for producer in producers {
					combined = combined
						.permute(with: producer.producer)
						.map { array, value in
							var array = array
							array.append(value)
							return array
						}
				}

				return combined
			}
	}
}

extension Signal where Value: EventProtocol, Value.Error == Error {
	/// Dematerializes the signal, like dematerialize(), but only yields inner
	/// Error events if no values were sent.
	internal func dematerializeErrorsIfEmpty() -> Signal<Value.Value, Error> {
		return Signal<Value.Value, Error> { observer, lifetime in
			var receivedValue = false
			var receivedError: Error?

			lifetime += self.observe { event in
				switch event {
				case let .value(innerEvent):
					switch innerEvent.event {
					case let .value(value):
						receivedValue = true
						observer.send(value: value)

					case let .failed(error):
						receivedError = error

					case .completed:
						observer.sendCompleted()

					case .interrupted:
						observer.sendInterrupted()
					}

				case let .failed(error):
					observer.send(error: error)

				case .completed:
					if let receivedError = receivedError, !receivedValue {
						observer.send(error: receivedError)
					}

					observer.sendCompleted()

				case .interrupted:
					observer.sendInterrupted()
				}
			}
		}
	}
}

extension SignalProducer where Value: EventProtocol, Value.Error == Error {
	/// Dematerializes the producer, like dematerialize(), but only yields inner
	/// Error events if no values were sent.
	internal func dematerializeErrorsIfEmpty() -> SignalProducer<Value.Value, Error> {
		return lift { $0.dematerializeErrorsIfEmpty() }
	}
}

extension Scanner {
	/// Returns the current line being scanned.
	internal var currentLine: String {
		// Force Foundation types, so we don't have to use Swift's annoying
		// string indexing.
		let nsString = string as NSString
		let scanRange: NSRange = NSRange(location: scanLocation, length: 0)
		let lineRange: NSRange = nsString.lineRange(for: scanRange)

		return nsString.substring(with: lineRange)
	}
}

extension Result where Error == CarthageError {
	/// Constructs a result from a throwing closure taking a `URL`, failing with `CarthageError` if throw occurs.
	/// - parameter carthageError: Defaults to `CarthageError.writeFailed`.
	internal init(
		at url: URL,
		carthageError: (URL, NSError) -> CarthageError = CarthageError.writeFailed,
		attempt closure: (URL) throws -> Value
	) {
		do {
			self = .success(try closure(url))
		} catch let error as NSError {
			self = .failure(carthageError(url, error))
		}
	}
}

extension URL {
	/// The type identifier of the receiver, or an error if it was unable to be
	/// determined.
	internal var typeIdentifier: Result<String, CarthageError> {
		var error: NSError?

		do {
			let typeIdentifier = try resourceValues(forKeys: [ .typeIdentifierKey ]).typeIdentifier
			if let identifier = typeIdentifier {
				return .success(identifier)
			}
		} catch let err as NSError {
			error = err
		}

		return .failure(.readFailed(self, error))
	}

	public func hasSubdirectory(_ possibleSubdirectory: URL) -> Bool {
		let standardizedSelf = self.standardizedFileURL
		let standardizedOther = possibleSubdirectory.standardizedFileURL

		let path = standardizedSelf.pathComponents
		let otherPath = standardizedOther.pathComponents
		if scheme == standardizedOther.scheme && path.count <= otherPath.count {
			return Array(otherPath[path.indices]) == path
		}

		return false
	}

	fileprivate func volumeSupportsFileCloning() throws -> Bool {
		guard #available(macOS 10.12, *) else { return false }

		let key = URLResourceKey.volumeSupportsFileCloningKey
		let values = try self.resourceValues(forKeys: [key]).allValues

		func error(failureReason: String) -> NSError {
			return NSError(
				domain: NSCocoaErrorDomain,
				code: CocoaError.fileReadUnknown.rawValue,
				userInfo: [NSURLErrorKey: self, NSLocalizedFailureReasonErrorKey: failureReason]
			)
		}

		guard values.count == 1 else {
			throw error(failureReason: "Expected single resource value: «actual count: \(values.count)».")
		}

		guard let volumeSupportsFileCloning = values[key] as? NSNumber else {
			throw error(failureReason: "Unable to extract a NSNumber from «\(String(describing: values.first))».")
		}

		return volumeSupportsFileCloning.boolValue
	}

	/// Returns the first `URL` to match `<self>/Headers/*-Swift.h`. Otherwise `nil`.
	internal func swiftHeaderURL() -> URL? {
		let headersURL = self.appendingPathComponent("Headers", isDirectory: true).resolvingSymlinksInPath()
		let dirContents = try? FileManager.default.contentsOfDirectory(at: headersURL, includingPropertiesForKeys: [], options: [])
		return dirContents?.first { $0.absoluteString.contains("-Swift.h") }
	}

	/// Returns the first `URL` to match `<self>/Modules/*.swiftmodule`. Otherwise `nil`.
	internal func swiftmoduleURL() -> URL? {
		let headersURL = self.appendingPathComponent("Modules", isDirectory: true).resolvingSymlinksInPath()
		let dirContents = try? FileManager.default.contentsOfDirectory(at: headersURL, includingPropertiesForKeys: [], options: [])
		return dirContents?.first { $0.absoluteString.contains("swiftmodule") }
	}
}

extension FileManager: ReactiveExtensionsProvider {
	@available(*, deprecated, message: "Use reactive.enumerator instead")
	public func carthage_enumerator(
		at url: URL, includingPropertiesForKeys keys: [URLResourceKey]? = nil,
		options: FileManager.DirectoryEnumerationOptions = [],
		catchErrors: Bool = false
	) -> SignalProducer<(FileManager.DirectoryEnumerator, URL), CarthageError> {
		return reactive.enumerator(at: url, includingPropertiesForKeys: keys, options: options, catchErrors: catchErrors)
	}

	// swiftlint:disable identifier_name
	/// rdar://32984063 When on APFS, `FileManager.copyItem(at:to)` can result in zero'd out binary files, due to the cloning functionality.
	/// To avoid this, we drop down to the copyfile c API, explicitly not passing the 'CLONE' flags so we always copy the data normally.
	/// - Parameter avoiding·rdar·32984063: When `false`, passthrough to Foundation’s `FileManager.copyItem(at:to:)`.
	internal func copyItem(at from: URL, to: URL, avoiding·rdar·32984063: Bool) throws {
		guard avoiding·rdar·32984063, try from.volumeSupportsFileCloning() else {
			return try self.copyItem(at: from, to: to)
		}

		try from.path.withCString { fromCStr in
			try to.path.withCString { toCStr in
				let state = copyfile_state_alloc()
				// Can't use COPYFILE_NOFOLLOW. Restriction relaxed to COPYFILE_NOFOLLOW_SRC
				// http://openradar.appspot.com/32984063
				let status = copyfile(fromCStr, toCStr, state, UInt32(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW_SRC))
				copyfile_state_free(state)
				if status < 0 {
					throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
				}
			}
		}
	}
}

extension Reactive where Base: FileManager {
	/// Creates a directory enumerator at the given URL. Sends each URL
	/// enumerated, along with the enumerator itself (so it can be introspected
	/// and modified as enumeration progresses).
	public func enumerator(
		at url: URL,
		includingPropertiesForKeys keys: [URLResourceKey]? = nil,
		options: FileManager.DirectoryEnumerationOptions = [],
		catchErrors: Bool = false
	) -> SignalProducer<(FileManager.DirectoryEnumerator, URL), CarthageError> {
		return SignalProducer { [base = self.base] observer, lifetime in
			let enumerator = base.enumerator(at: url, includingPropertiesForKeys: keys, options: options) { url, error in
				if catchErrors {
					return true
				} else {
					observer.send(error: CarthageError.readFailed(url, error as NSError))
					return false
				}
			}!

			while !lifetime.hasEnded {
				if let url = enumerator.nextObject() as? URL {
					let value = (enumerator, url)
					observer.send(value: value)
				} else {
					break
				}
			}

			observer.sendCompleted()
		}
	}

	/// Creates a temporary directory with the given template name. Sends the
	/// URL of the temporary directory and completes if successful, else errors.
	///
	/// The template name should adhere to the format required by the mkdtemp()
	/// function.
	public func createTemporaryDirectoryWithTemplate(_ template: String) -> SignalProducer<URL, CarthageError> {
		return SignalProducer { [base = self.base] () -> Result<String, CarthageError> in
			let temporaryDirectory: NSString
			if #available(macOS 10.12, *) {
				temporaryDirectory = base.temporaryDirectory.path as NSString
			} else {
				temporaryDirectory = NSTemporaryDirectory() as NSString
			}

			var temporaryDirectoryTemplate: ContiguousArray<CChar> = temporaryDirectory.appendingPathComponent(template).utf8CString

			let result: UnsafeMutablePointer<Int8>? = temporaryDirectoryTemplate
				.withUnsafeMutableBufferPointer { (template: inout UnsafeMutableBufferPointer<CChar>) -> UnsafeMutablePointer<CChar> in
					mkdtemp(template.baseAddress)
				}

			if result == nil {
				return .failure(.taskError(.posixError(errno)))
			}

			let temporaryPath = temporaryDirectoryTemplate.withUnsafeBufferPointer { (ptr: UnsafeBufferPointer<CChar>) -> String in
				return String(validatingUTF8: ptr.baseAddress!)!
			}

			return .success(temporaryPath)
		}
		.map { URL(fileURLWithPath: $0, isDirectory: true) }
	}
}

private let defaultSessionError = NSError(domain: Constants.bundleIdentifier, code: 1, userInfo: nil)

extension Reactive where Base: URLSession {
	/// Returns a SignalProducer which performs a downloadTask associated with an
	/// `NSURLSession`
	///
	/// - parameters:
	///   - request: A request that will be performed when the producer is
	///              started
	///
	/// - returns: A producer that will execute the given request once for each
	///            invocation of `start()`.
	///
	/// - note: This method will not send an error event in the case of a server
	///         side error (i.e. when a response with status code other than
	///         200...299 is received).
	internal func download(with request: URLRequest) -> SignalProducer<(URL, URLResponse), AnyError> {
		return SignalProducer { [base = self.base] observer, lifetime in
			let task = base.downloadTask(with: request) { url, response, error in
				if let url = url, let response = response {
					observer.send(value: (url, response))
					observer.sendCompleted()
				} else {
					observer.send(error: AnyError(error ?? defaultSessionError))
				}
			}

			lifetime.observeEnded {
				task.cancel()
			}
			task.resume()
		}
	}
}
