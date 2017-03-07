//
//  FrameworkExtensions.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-31.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import Result
import ReactiveSwift

extension String {
	/// Returns a producer that will enumerate each line of the receiver, then
	/// complete.
	internal var linesProducer: SignalProducer<String, NoError> {
		return SignalProducer { observer, disposable in
			self.enumerateLines { line, stop in
				observer.send(value: line)

				if disposable.isDisposed {
					stop = true
				}
			}

			observer.sendCompleted()
		}
	}

	/// Strips off a trailing string, if present.
	internal func stripping(suffix: String) -> String {
		if hasSuffix(suffix) {
			let end = characters.index(endIndex, offsetBy: -suffix.characters.count)
			return self[startIndex..<end]
		} else {
			return self
		}
	}
}

/// Merges `rhs` into `lhs` and returns the result.
internal func combineDictionaries<K, V>(_ lhs: [K: V], rhs: [K: V]) -> [K: V] {
	var result = lhs
	for (key, value) in rhs {
		result.updateValue(value, forKey: key)
	}

	return result
}

extension SignalProtocol {
	/// Sends each value that occurs on `signal` combined with each value that
	/// occurs on `otherSignal` (repeats included).
	fileprivate func permute<U>(with otherSignal: Signal<U, Error>) -> Signal<(Value, U), Error> {
		return Signal { observer in
			let lock = NSLock()
			lock.name = "org.carthage.CarthageKit.permute"

			var signalValues: [Value] = []
			var signalCompleted = false
			var otherValues: [U] = []
			var otherCompleted = false

			let compositeDisposable = CompositeDisposable()

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

			return compositeDisposable
		}
	}
}

extension SignalProducerProtocol {
	/// Sends each value that occurs on `producer` combined with each value that
	/// occurs on `otherProducer` (repeats included).
	fileprivate func permute<U>(with otherProducer: SignalProducer<U, Error>) -> SignalProducer<(Value, U), Error> {
		return lift(Signal.permute(with:))(otherProducer)
	}
	
	/// Sends a boolean of whether the producer succeeded or failed.
	internal func succeeded() -> SignalProducer<Bool, NoError> {
		return self
			.then(SignalProducer<Bool, Error>.init(value: true))
			.flatMapError { _ in .init(value: false) }
	}
}

extension SignalProducerProtocol where Value: SignalProducerProtocol, Error == Value.Error {
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

extension SignalProtocol where Value: EventProtocol, Value.Error == Error {
	/// Dematerializes the signal, like dematerialize(), but only yields inner
	/// Error events if no values were sent.
	internal func dematerializeErrorsIfEmpty() -> Signal<Value.Value, Error> {
		return Signal { observer in
			var receivedValue = false
			var receivedError: Error? = nil

			return self.observe { event in
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

extension SignalProducerProtocol where Value: EventProtocol, Value.Error == Error {
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
		let scanRange: NSRange = NSMakeRange(scanLocation, 0)
		let lineRange: NSRange = nsString.lineRange(for: scanRange)

		return nsString.substring(with: lineRange)
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

	/// Returns the first `URL` to match `<self>/Headers/*-Swift.h`. Otherwise `nil`.
	internal func swiftHeaderURL() -> URL? {
		let headersURL = self.appendingPathComponent("Headers", isDirectory: true).resolvingSymlinksInPath()
		let dirContents = try? FileManager.default.contentsOfDirectory(at: headersURL, includingPropertiesForKeys: [], options: [])
		return dirContents?.filter { $0.absoluteString.contains("-Swift.h") }.first
	}

	/// Returns the first `URL` to match `<self>/Modules/*.swiftmodule`. Otherwise `nil`.
	internal func swiftmoduleURL() -> URL? {
		let headersURL = self.appendingPathComponent("Modules", isDirectory: true).resolvingSymlinksInPath()
		let dirContents = try? FileManager.default.contentsOfDirectory(at: headersURL, includingPropertiesForKeys: [], options: [])
		return dirContents?.filter { $0.absoluteString.contains("swiftmodule") }.first
	}
}

extension FileManager: ReactiveExtensionsProvider {
	@available(*, deprecated, message: "Use reactive.enumerator instead")
	public func carthage_enumerator(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]? = nil, options: FileManager.DirectoryEnumerationOptions = [], catchErrors: Bool = false) -> SignalProducer<(FileManager.DirectoryEnumerator, URL), CarthageError> {
		return reactive.enumerator(at: url, includingPropertiesForKeys: keys, options: options, catchErrors: catchErrors)
	}
}

extension Reactive where Base: FileManager {
	/// Creates a directory enumerator at the given URL. Sends each URL
	/// enumerated, along with the enumerator itself (so it can be introspected
	/// and modified as enumeration progresses).
	public func enumerator(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]? = nil, options: FileManager.DirectoryEnumerationOptions = [], catchErrors: Bool = false) -> SignalProducer<(FileManager.DirectoryEnumerator, URL), CarthageError> {
		return SignalProducer { [base = self.base] observer, disposable in
			let enumerator = base.enumerator(at: url, includingPropertiesForKeys: keys, options: options) { (url, error) in
				if catchErrors {
					return true
				} else {
					observer.send(error: CarthageError.readFailed(url, error as NSError))
					return false
				}
			}!

			while !disposable.isDisposed {
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
}

private let defaultSessionError = NSError(domain: CarthageKitBundleIdentifier,
                                          code: 1,
                                          userInfo: nil)

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
		return SignalProducer { [base = self.base] observer, disposable in
			let task = base.downloadTask(with: request) { url, response, error in
				if let url = url, let response = response {
					observer.send(value: (url, response))
					observer.sendCompleted()
				} else {
					observer.send(error: AnyError(error ?? defaultSessionError))
				}
			}

			disposable += {
				task.cancel()
			}
			task.resume()
		}
	}
}

/// Creates a counted set from a sequence. The counted set is represented as a
/// dictionary where the keys are elements from the sequence and values count
/// how many times elements are present in the sequence.
internal func buildCountedSet<S: Sequence>(_ sequence: S) -> [S.Iterator.Element: Int] {
	return sequence.reduce([:]) { set, elem in
		var set = set
		if let count = set[elem] {
			set[elem] = count + 1
		}
		else {
			set[elem] = 1
		}
		return set
	}
}
