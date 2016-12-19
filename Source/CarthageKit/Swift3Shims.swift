#if swift(>=3)
#else
	import Foundation
	import PrettyColors
	import Result
	import ReactiveCocoa
	import ReactiveTask
	import Tentacle

	// MARK: - Stdlib
	
	internal extension String {
		func components(separatedBy separator: String) -> [String] {
			return componentsSeparatedByString(separator)
		}

		func data(using encoding: NSStringEncoding, allowLossyConversion: Bool = false) -> Data? {
			return dataUsingEncoding(encoding, allowLossyConversion: allowLossyConversion)
		}

		func lowercased() -> String {
			return lowercaseString
		}

		func range(of aString: String) -> Range<Index>? {
			return rangeOfString(aString)
		}

		func substring(from index: Index) -> String {
			return substringFromIndex(index)
		}
		
		func trimmingCharacters(in set: CharacterSet) -> String {
			return stringByTrimmingCharactersInSet(set)
		}

		func write(to url: URL, atomically useAuxiliaryFile: Bool, encoding enc: NSStringEncoding) throws {
			try writeToURL(url, atomically: useAuxiliaryFile, encoding: enc)
		}

		func write(toFile path: String, atomically useAuxiliaryFile: Bool, encoding enc: NSStringEncoding) throws {
			try writeToFile(path, atomically: useAuxiliaryFile, encoding: enc)
		}
	}

	extension SequenceType where Generator.Element == String {
		func joined(separator separator: String) -> String {
			return joinWithSeparator(separator)
		}
	}

	extension SequenceType where Generator.Element: Comparable {
		func sorted() -> [Generator.Element] {
			return sort()
		}
	}

	extension CollectionType {
		func split(maxSplits maxSplits: Int = .max, omittingEmptySubsequences: Bool = true, whereSeparator isSeparator: (Generator.Element) throws -> Bool) rethrows -> [SubSequence] {
			return try split(maxSplits, allowEmptySlices: !omittingEmptySubsequences, isSeparator: isSeparator)
		}
	}

	extension CollectionType where Generator.Element: Equatable {
		func index(of element: Generator.Element) -> Index? {
			return indexOf(element)
		}
	}

	extension Set {
		func isSubset(of other: Set<Element>) -> Bool {
			return isSubsetOf(other)
		}

		mutating func formUnion<S: SequenceType where S.Generator.Element == Element>(other: S) {
			unionInPlace(other)
		}
	}

	// MARK: - Foundation

	internal typealias Bundle = NSBundle
	internal extension Bundle {
		convenience init(for aClass: AnyClass) {
			self.init(forClass: aClass)
		}

		convenience init?(url: URL) {
			self.init(URL: url)
		}

		func url(forResource name: String?, withExtension ext: String?) -> URL? {
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

	internal typealias ComparisonResult = NSComparisonResult
	internal extension ComparisonResult {
		static var orderedAscending: ComparisonResult { return .OrderedAscending }
		static var orderedSame: ComparisonResult { return .OrderedSame }
		static var orderedDescending: ComparisonResult { return .OrderedDescending }
	}

	public typealias Data = NSData

	internal typealias Date = NSDate

	internal typealias FileHandle = NSFileHandle
	internal extension FileHandle {
		class var standardError: FileHandle { return fileHandleWithStandardError() }
		class var standardOutput: FileHandle { return fileHandleWithStandardOutput() }

		func write(data: Data) {
			writeData(data)
		}
	}

	internal typealias FileManager = NSFileManager
	internal extension FileManager {
		class var `default`: FileManager { return defaultManager() }

		@nonobjc func contentsOfDirectory(atPath path: String) throws -> [String] {
			return try contentsOfDirectoryAtPath(path)
		}

		func copyItem(at srcURL: URL, to dstURL: URL) throws {
			try copyItemAtURL(srcURL, toURL: dstURL)
		}

		func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [String : AnyObject]? = nil) throws {
			try createDirectoryAtURL(url, withIntermediateDirectories: createIntermediates, attributes: attributes)
		}

		@nonobjc func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool, attributes: [String : AnyObject]? = nil) throws {
			try createDirectoryAtPath(path, withIntermediateDirectories: createIntermediates, attributes: attributes)
		}

		func createSymbolicLink(at url: URL, withDestinationURL destURL: URL) throws {
			try createSymbolicLinkAtURL(url, withDestinationURL: destURL)
		}

		@nonobjc func createSymbolicLink(atPath path: String, withDestinationPath destPath: String) throws {
			try createSymbolicLinkAtPath(path, withDestinationPath: destPath)
		}

		@nonobjc func destinationOfSymbolicLink(atPath path: String) throws -> String {
			return try destinationOfSymbolicLinkAtPath(path)
		}

		func enumerator(at url: URL, includingPropertiesForKeys keys: [String]?, options mask: NSDirectoryEnumerationOptions = [], errorHandler handler: ((URL, NSError) -> Bool)? = nil) -> NSDirectoryEnumerator? {
			return enumeratorAtURL(url, includingPropertiesForKeys: keys, options: mask, errorHandler: handler)
		}

		@nonobjc func fileExists(atPath path: String) -> Bool {
			return fileExistsAtPath(path)
		}

		@nonobjc func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>) -> Bool {
			return fileExistsAtPath(path, isDirectory: isDirectory)
		}

		@nonobjc func isWritableFile(atPath path: String) -> Bool {
			return isWritableFileAtPath(path)
		}

		func moveItem(at srcURL: URL, to dstURL: URL) throws {
			try moveItemAtURL(srcURL, toURL: dstURL)
		}

		func removeItem(at url: URL) throws {
			try removeItemAtURL(url)
		}

		func trashItem(at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<URL?>) throws {
			try trashItemAtURL(url, resultingItemURL: outResultingURL)
		}

		func url(for directory: NSSearchPathDirectory, in domain: NSSearchPathDomainMask, appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL {
			return try URLForDirectory(directory, inDomain: domain, appropriateForURL: url, create: shouldCreate)
		}
	}

	extension NSSearchPathDirectory {
		static let cachesDirectory = NSSearchPathDirectory.CachesDirectory
	}

	extension NSSearchPathDomainMask {
		static let userDomainMask = NSSearchPathDomainMask.UserDomainMask
	}

	internal extension NSRegularExpression {
		func firstMatch(in string: String, options: NSMatchingOptions = [], range: NSRange) -> NSTextCheckingResult? {
			return firstMatchInString(string, options: options, range: range)
		}

		func matches(in string: String, options: NSMatchingOptions = [], range: NSRange) -> [NSTextCheckingResult] {
			return matchesInString(string, options: options, range: range)
		}
	}

	internal extension NSTextCheckingResult {
		func rangeAt(idx: Int) -> NSRange {
			return rangeAtIndex(idx)
		}
	}

	internal extension NSString {
		var deletingLastPathComponent: String {
			return stringByDeletingLastPathComponent
		}

		var expandingTildeInPath: String {
			return stringByExpandingTildeInPath
		}

		func appendingPathComponent(str: String) -> String {
			return stringByAppendingPathComponent(str)
		}

		func appendingPathExtension(str: String) -> String? {
			return stringByAppendingPathExtension(str)
		}

		func components(separatedBy separator: String) -> [String] {
			return componentsSeparatedByString(separator)
		}

		func lineRange(for range: NSRange) -> NSRange {
			return lineRangeForRange(range)
		}

		func substring(with range: NSRange) -> String {
			return substringWithRange(range)
		}
	}

	internal typealias ProcessInfo = NSProcessInfo
	internal extension ProcessInfo {
		@nonobjc class var processInfo: ProcessInfo { return processInfo() }
	}

	public typealias Scanner = NSScanner
	internal extension Scanner {
		@nonobjc var isAtEnd: Bool { return atEnd }

		func scanString(string: String, into result: AutoreleasingUnsafeMutablePointer<NSString?>) -> Bool {
			return scanString(string, intoString: result)
		}

		func scanUpTo(string: String, into result: AutoreleasingUnsafeMutablePointer<NSString?>) -> Bool {
			return scanUpToString(string, intoString: result)
		}

		func scanCharacters(from set: CharacterSet, into result: AutoreleasingUnsafeMutablePointer<NSString?>) -> Bool {
			return scanCharactersFromSet(set, intoString: result)
		}

		func scanUpToCharacters(from set: CharacterSet, into result: AutoreleasingUnsafeMutablePointer<NSString?>) -> Bool {
			return scanUpToCharactersFromSet(set, intoString: result)
		}
	}

	public typealias URL = NSURL
	internal extension URL {
		@nonobjc var isFileURL: Bool { return fileURL }

		var standardizedFileURL : URL {
			return URLByStandardizingPath ?? self
		}

		// https://github.com/apple/swift-corelibs-foundation/blob/swift-3.0.1-RELEASE/Foundation/URL.swift#L607-L619
		var carthage_path: String {
			if let parameterString = parameterString {
				return (path ?? "") + ";" + parameterString
			}
			return path ?? ""
		}

		var carthage_lastPathComponent: String {
			return lastPathComponent ?? ""
		}

		var carthage_pathComponents: [String] {
			return pathComponents ?? []
		}

		func appendingPathExtension(pathExtension: String) -> URL {
			return URLByAppendingPathExtension(pathExtension)!
		}

		func appendingPathComponent(pathComponent: String) -> URL {
			return URLByAppendingPathComponent(pathComponent)!
		}

		func appendingPathComponent(pathComponent: String, isDirectory: Bool) -> URL {
			return URLByAppendingPathComponent(pathComponent, isDirectory: isDirectory)!
		}

		func deletingLastPathComponent() -> URL {
			return URLByDeletingLastPathComponent ?? self
		}

		func deletingPathExtension() -> URL {
			return URLByDeletingPathExtension ?? self
		}

		func removeCachedResourceValue(forKey key: URLResourceKey) {
			removeCachedResourceValueForKey(key.rawValue)
		}

		func resolvingSymlinksInPath() -> URL {
			return URLByResolvingSymlinksInPath ?? self
		}

		func resourceValues(forKeys keys: Set<URLResourceKey>) throws -> URLResourceValues {
			return URLResourceValues(url: self)
		}

		func withUnsafeFileSystemRepresentation<ResultType>(block: (UnsafePointer<Int8>?) throws -> ResultType) rethrows -> ResultType {
			return try block(fileSystemRepresentation)
		}
	}

	// https://developer.apple.com/reference/foundation/URLResourceKey
	internal struct URLResourceKey: Hashable {
		let rawValue: String

		static let isDirectoryKey: URLResourceKey = URLResourceKey(rawValue: NSURLIsDirectoryKey)
		static let isSymbolicLinkKey: URLResourceKey = URLResourceKey(rawValue: NSURLIsSymbolicLinkKey)
		static let nameKey: URLResourceKey = URLResourceKey(rawValue: NSURLNameKey)
		static let typeIdentifierKey: URLResourceKey = URLResourceKey(rawValue: NSURLTypeIdentifierKey)

		var hashValue: Int { return rawValue.hashValue }
	}

	func ==(lhs: URLResourceKey, rhs: URLResourceKey) -> Bool {
		return lhs.rawValue == rhs.rawValue
	}

	// https://developer.apple.com/reference/foundation/URLResourceValues
	internal struct URLResourceValues {
		private let url: URL

		private func get<T>(forKey key: URLResourceKey) -> T? {
			do {
				var result: AnyObject?
				try url.getResourceValue(&result, forKey: key.rawValue)
				return result as? T
			} catch {
				return nil
			}
		}

		var isDirectory: Bool? {
			return get(forKey: .isDirectoryKey)
		}

		var isSymbolicLink: Bool? {
			return get(forKey: .isSymbolicLinkKey)
		}

		var name: String? {
			return get(forKey: .nameKey)
		}

		var typeIdentifier: String? {
			return get(forKey: .typeIdentifierKey)
		}
	}

	public typealias UUID = NSUUID
	internal extension UUID {
		convenience init?(uuidString string: String) {
			self.init(UUIDString: string)
		}

		var uuidString: String { return UUIDString }
	}

	// MARK: - PrettyColors

	internal extension PrettyColors.Color.Named.Color {
		static var green: PrettyColors.Color.Named.Color { return .Green }
		static var yellow: PrettyColors.Color.Named.Color { return .Yellow }
		static var blue: PrettyColors.Color.Named.Color { return .Blue }
	}

	internal extension StyleParameter {
		static var bold: StyleParameter { return .Bold }
		static var underlined: StyleParameter { return .Underlined }
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
		func launch(standardInput standardInput: SignalProducer<Data, NoError>? = nil) -> SignalProducer<TaskEvent<Data>, TaskError> {
			return launchTask(self, standardInput: standardInput)
		}
	}

	// MARK: - Tentacle

	internal extension Client {
		var isAuthenticated: Bool { return authenticated }

		func releases(in repository: Repository, page: UInt = 1, perPage: UInt = 30) -> SignalProducer<(Response, [Release]), Error> {
			return releasesInRepository(repository, page: page, perPage: perPage)
		}

		func release(forTag tag: String, in repository: Repository) -> SignalProducer<(Response, Release), Error> {
			return releaseForTag(tag, inRepository: repository)
		}

		func download(asset asset: Release.Asset) -> SignalProducer<URL, Error> {
			return downloadAsset(asset)
		}
	}

	internal extension Release {
		var isDraft: Bool { return draft }
	}

	internal extension Server {
		static var dotCom: Server { return .DotCom }
		static func enterprise(url url: NSURL) -> Server {
			return .Enterprise(url: url)
		}
	}
#endif
