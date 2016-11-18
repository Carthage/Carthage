#if swift(>=3)
#else
	import Foundation
	import Result
	import ReactiveCocoa
	import ReactiveTask

	// MARK: - Foundation

	internal typealias Bundle = NSBundle
	internal extension Bundle {
		convenience init(for aClass: AnyClass) {
			self.init(forClass: aClass)
		}

		convenience init?(url: NSURL) {
			self.init(URL: url)
		}

		func url(forResource name: String?, withExtension ext: String?) -> NSURL? {
			return URLForResource(name, withExtension: ext)
		}

		func object(forInfoDictionaryKey key: String) -> Any? {
			return objectForInfoDictionaryKey(key)
		}

		static var main: Bundle { return mainBundle() }
	}

	internal typealias CharacterSet = NSCharacterSet
	internal extension CharacterSet {
		class var decimalDigits: CharacterSet { return decimalDigitCharacterSet() }
		class var letters: CharacterSet { return letterCharacterSet() }
		class var newlines: CharacterSet { return newlineCharacterSet() }
		class var whitespaces: CharacterSet { return whitespaceCharacterSet() }
		class var whitespacesAndNewlines: CharacterSet { return whitespaceAndNewlineCharacterSet() }

		var inverted: CharacterSet { return invertedSet }

		convenience init(charactersIn string: String) {
			self.init(charactersInString: string)
		}
	}
	internal extension NSMutableCharacterSet {
		class func alphanumeric() -> NSMutableCharacterSet { return alphanumericCharacterSet() }

		func addCharacters(in aString: String) {
			return addCharactersInString(aString)
		}

		func formUnion(with otherSet: CharacterSet) {
			return formUnionWithCharacterSet(otherSet)
		}
	}

	internal typealias FileManager = NSFileManager
	internal extension FileManager {
		class var `default`: FileManager { return defaultManager() }

		@nonobjc func contentsOfDirectory(atPath path: String) throws -> [String] {
			return try contentsOfDirectoryAtPath(path)
		}

		func copyItem(at srcURL: NSURL, to dstURL: NSURL) throws {
			try copyItemAtURL(srcURL, toURL: dstURL)
		}

		func createDirectory(at url: NSURL, withIntermediateDirectories createIntermediates: Bool, attributes: [String : AnyObject]? = nil) throws {
			try createDirectoryAtURL(url, withIntermediateDirectories: createIntermediates, attributes: attributes)
		}

		@nonobjc func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool, attributes: [String : AnyObject]? = nil) throws {
			try createDirectoryAtPath(path, withIntermediateDirectories: createIntermediates, attributes: attributes)
		}

		func createSymbolicLink(at url: NSURL, withDestinationURL destURL: NSURL) throws {
			try createSymbolicLinkAtURL(url, withDestinationURL: destURL)
		}

		@nonobjc func createSymbolicLink(atPath path: String, withDestinationPath destPath: String) throws {
			try createSymbolicLinkAtPath(path, withDestinationPath: destPath)
		}

		@nonobjc func destinationOfSymbolicLink(atPath path: String) throws -> String {
			return try destinationOfSymbolicLinkAtPath(path)
		}

		func enumerator(at url: NSURL, includingPropertiesForKeys keys: [String]?, options mask: NSDirectoryEnumerationOptions = [], errorHandler handler: ((NSURL, NSError) -> Bool)? = nil) -> NSDirectoryEnumerator? {
			return enumeratorAtURL(url, includingPropertiesForKeys: keys, options: mask, errorHandler: handler)
		}

		@nonobjc func fileExists(atPath path: String) -> Bool {
			return fileExistsAtPath(path)
		}

		@nonobjc func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>) -> Bool {
			return fileExistsAtPath(path, isDirectory: isDirectory)
		}

		func moveItem(at srcURL: NSURL, to dstURL: NSURL) throws {
			try moveItemAtURL(srcURL, toURL: dstURL)
		}

		func removeItem(at url: NSURL) throws {
			try removeItemAtURL(url)
		}

		func trashItem(at url: NSURL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>) throws {
			try trashItemAtURL(url, resultingItemURL: outResultingURL)
		}
	}

	// MARK: - Result

	internal extension Result {
		static func success(value: Value) -> Result<Value, Error> {
			return .Success(value)
		}

		static func failure(error: Error) -> Result<Value, Error> {
			return .Failure(error)
		}
	}

	// MARK: - ReactiveSwift

	internal typealias SignalProtocol = SignalType
	internal typealias SignalProducerProtocol = SignalProducerType
	internal typealias SchedulerProtocol = SchedulerType
	internal typealias DateSchedulerProtocol = DateSchedulerType
	internal typealias OptionalProtocol = OptionalType
	internal typealias EventProtocol = EventType

	internal extension Disposable {
		var isDisposed: Bool { return disposed }
	}

	internal extension CompositeDisposable {
		func add(d: Disposable?) -> DisposableHandle {
			return addDisposable(d)
		}
	}

	internal extension Observer {
		func send(value value: Value) {
			sendNext(value)
		}

		func send(error error: Error) {
			sendFailed(error)
		}
	}

	internal extension SignalProtocol {
		func take(first count: Int) -> Signal<Value, Error> {
			return take(count)
		}
	}

	internal extension SignalProtocol where Error == NoError {
		func observeValues(value: (Value) -> Void) -> Disposable? {
			return observeNext(value)
		}
	}

	internal extension SignalProducerProtocol {
		func take(first count: Int) -> SignalProducer<Value, Error> {
			return take(count)
		}

		func take(last count: Int) -> SignalProducer<Value, Error> {
			return takeLast(count)
		}

		func skip(first count: Int) -> SignalProducer<Value, Error> {
			return skip(count)
		}

		func retry(upTo count: Int) -> SignalProducer<Value, Error> {
			return retry(count)
		}

		func observe(on scheduler: SchedulerProtocol) -> SignalProducer<Value, Error> {
			return observeOn(scheduler)
		}

		func start(on scheduler: SchedulerProtocol) -> SignalProducer<Value, Error> {
			return startOn(scheduler)
		}

		func zip<U>(with other: SignalProducer<U, Error>) -> SignalProducer<(Value, U), Error> {
			return zipWith(other)
		}

		func skip(while predicate: (Value) -> Bool) -> SignalProducer<Value, Error> {
			return skipWhile(predicate)
		}

		func take(while predicate: (Value) -> Bool) -> SignalProducer<Value, Error> {
			return takeWhile(predicate)
		}

		func timeout(after interval: NSTimeInterval, raising error: Error, on scheduler: DateSchedulerProtocol) -> SignalProducer<Value, Error> {
			return timeoutWithError(error, afterInterval: interval, onScheduler: scheduler)
		}

		static func combineLatest<B>(a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>) -> SignalProducer<(Value, B), Error> {
			return ReactiveCocoa.combineLatest(a, b)
		}

		static func combineLatest<B, C>(a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>, _ c: SignalProducer<C, Error>) -> SignalProducer<(Value, B, C), Error> {
			return ReactiveCocoa.combineLatest(a, b, c)
		}

		static func zip<B>(a: SignalProducer<Value, Error>, _ b: SignalProducer<B, Error>) -> SignalProducer<(Value, B), Error> {
			return ReactiveCocoa.zip(a, b)
		}
	}

	internal extension SignalProducerProtocol where Value: OptionalProtocol {
		func skipNil() -> SignalProducer<Value.Wrapped, Error> {
			return ignoreNil()
		}
	}

	internal extension FlattenStrategy {
		static var merge: FlattenStrategy { return .Merge }
		static var concat: FlattenStrategy { return .Concat }
		static var latest: FlattenStrategy { return .Latest }
	}

	internal extension QueueScheduler {
		static var main: QueueScheduler { return mainQueueScheduler }
	}

	// MARK: - ReactiveTask

	internal extension TaskEvent {
		static func success(value: T) -> TaskEvent<T> {
			return .Success(value)
		}
	}

	internal extension TaskError {
		static func posixError(code: Int32) -> TaskError {
			return .POSIXError(code)
		}
	}

	internal extension Task {
		func launch(standardInput standardInput: SignalProducer<NSData, NoError>? = nil) -> SignalProducer<TaskEvent<NSData>, TaskError> {
			return launchTask(self, standardInput: standardInput)
		}
	}
#endif
