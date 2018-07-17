import Foundation
import Result

/// The relative path to a project's checked out dependencies.
public let carthageProjectCheckoutsPath = "Carthage/Checkouts"

/// Represents a Cartfile, which is a specification of a project's dependencies
/// and any other settings Carthage needs to build it.
public struct Cartfile {
	
	/// Any text following this character is considered a comment
	static let commentIndicator = "#"
	
	/// The dependencies listed in the Cartfile.
	public var dependencies: [Dependency: VersionSpecifier]

	public init(dependencies: [Dependency: VersionSpecifier] = [:]) {
		self.dependencies = dependencies
	}

	/// Returns the location where Cartfile should exist within the given
	/// directory.
	public static func url(in directoryURL: URL) -> URL {
		return directoryURL.appendingPathComponent("Cartfile")
	}

	/// Attempts to parse Cartfile information from a string.
	public static func from(string: String) -> Result<Cartfile, CarthageError> {
		var dependencies: [Dependency: VersionSpecifier] = [:]
		var duplicates: [Dependency] = []
		var result: Result<(), CarthageError> = .success(())

		string.enumerateLines { line, stop in
			let scannerWithComments = Scanner(string: line)

			if scannerWithComments.scanString(Cartfile.commentIndicator, into: nil) {
				// Skip the rest of the line.
				return
			}

			if scannerWithComments.isAtEnd {
				// The line was all whitespace.
				return
			}
			
			guard let remainingString = scannerWithComments.remainingSubstring.map(String.init) else {
				result = .failure(CarthageError.internalError(
					description: "Can NSScanner split an extended grapheme cluster? If it does, this will be the error…"
				))
				stop = true
				return
			}
			
			let scannerWithoutComments = Scanner(
				string: remainingString.strippingTrailingCartfileComment
					.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
			)

			switch Dependency.from(scannerWithoutComments).fanout(VersionSpecifier.from(scannerWithoutComments)) {
			case let .success((dependency, version)):
				if case .binary = dependency, case .gitReference = version {
					result = .failure(
						CarthageError.parseError(
							description: "binary dependencies cannot have a git reference for the version specifier in line: \(scannerWithComments.currentLine)"
						)
					)
					stop = true
					return
				}

				if dependencies[dependency] == nil {
					dependencies[dependency] = version
				} else {
					duplicates.append(dependency)
				}

			case let .failure(error):
				result = .failure(CarthageError(scannableError: error))
				stop = true
				return
			}

			if !scannerWithoutComments.isAtEnd {
				result = .failure(CarthageError.parseError(description: "unexpected trailing characters in line: \(line)"))
				stop = true
			}
		}

		return result.flatMap { _ in
			if !duplicates.isEmpty {
				return .failure(.duplicateDependencies(duplicates.map { DuplicateDependency(dependency: $0, locations: []) }))
			}
			return .success(Cartfile(dependencies: dependencies))
		}
	}

	/// Attempts to parse a Cartfile from a file at a given URL.
	public static func from(file cartfileURL: URL) -> Result<Cartfile, CarthageError> {
		return Result(attempt: { try String(contentsOf: cartfileURL, encoding: .utf8) })
			.mapError { .readFailed(cartfileURL, $0) }
			.flatMap(Cartfile.from(string:))
			.mapError { error in
				guard case let .duplicateDependencies(dupes) = error else { return error }

				let dependencies = dupes
					.map { dupe in
						return DuplicateDependency(
							dependency: dupe.dependency,
							locations: [ cartfileURL.path ]
						)
					}
				return .duplicateDependencies(dependencies)
			}
	}

	/// Appends the contents of another Cartfile to that of the receiver.
	public mutating func append(_ cartfile: Cartfile) {
		for (dependency, version) in cartfile.dependencies {
			dependencies[dependency] = version
		}
	}
}

/// Returns an array containing dependencies that are listed in both arguments.
public func duplicateDependenciesIn(_ cartfile1: Cartfile, _ cartfile2: Cartfile) -> [Dependency] {
	let projects1 = cartfile1.dependencies.keys
	let projects2 = cartfile2.dependencies.keys
	return Array(Set(projects1).intersection(Set(projects2)))
}

/// Represents a parsed Cartfile.resolved, which specifies which exact version was
/// checked out for each dependency.
public struct ResolvedCartfile {
	/// The dependencies listed in the Cartfile.resolved.
	public let dependencies: [Dependency: PinnedVersion]
	private let dependenciesByName: [String: Dependency]

	public init(dependencies: [Dependency: PinnedVersion]) {
		self.dependencies = dependencies
		var dependenciesByName = [String: Dependency]()
		for (dependency, _) in dependencies {
			dependenciesByName[dependency.name] = dependency
		}
		self.dependenciesByName = dependenciesByName
	}

	public func dependency(for name: String) -> Dependency? {
		return dependenciesByName[name]
	}

	public func version(for name: String) -> PinnedVersion? {
		if let dependency = dependency(for: name) {
			return dependencies[dependency]
		} else {
			return nil
		}
	}

	/// Returns the location where Cartfile.resolved should exist within the given
	/// directory.
	public static func url(in directoryURL: URL) -> URL {
		return directoryURL.appendingPathComponent("Cartfile.resolved")
	}

	/// Attempts to parse Cartfile.resolved information from a string.
	public static func from(string: String) -> Result<ResolvedCartfile, CarthageError> {
		var dependencies = [Dependency: PinnedVersion]()
		var result: Result<(), CarthageError> = .success(())

		let scanner = Scanner(string: string)
		scannerLoop: while !scanner.isAtEnd {
			switch Dependency.from(scanner).fanout(PinnedVersion.from(scanner)) {
			case let .success((dep, version)):
				dependencies[dep] = version

			case let .failure(error):
				result = .failure(CarthageError(scannableError: error))
				break scannerLoop
			}
		}
		return result.map { _ in ResolvedCartfile(dependencies: dependencies) }
	}
}

extension ResolvedCartfile: CustomStringConvertible {
	public var description: String {
		return dependencies
			.sorted { $0.key.description < $1.key.description }
			.map { "\($0.key) \($0.value)\n" }
			.joined(separator: "")
	}
}


extension String {
	
	/// Returns self without any potential trailing Cartfile comment. A Cartfile
	/// comment starts with the first `commentIndicator` that is not embedded in any quote
	var strippingTrailingCartfileComment: String {
		
		// Since the Cartfile syntax doesn't support nested quotes, such as `"version-\"alpha\""`,
		// simply consider any odd-number occurence of a quote as a quote-start, and any
		// even-numbered occurrence of a quote as quote-end.
		// The comment indicator (e.g. `#`) is the start of a comment if it's not nested in quotes.
		// The following code works also for comment indicators that are are more than one character
		// long (e.g. double slashes).
		
		let quote = "\""
		
		// Splitting the string by quote will make odd-numbered chunks outside of quotes, and
		// even-numbered chunks inside of quotes.
		// `omittingEmptySubsequences` is needed to maintain this property even in case of empty quotes.
		let quoteDelimitedChunks = self.split(
			separator: quote.first!,
			maxSplits: Int.max,
			omittingEmptySubsequences: false
		)
		
		for (offset, chunk) in quoteDelimitedChunks.enumerated() {
			let isInQuote = offset % 2 == 1 // even chunks are not in quotes, see comment above
			if isInQuote {
				continue // don't consider comment indicators inside quotes
			}
			if let range = chunk.range(of: Cartfile.commentIndicator) {
				// there is a comment, return everything before its position
				let advancedOffset = (..<offset).relative(to: quoteDelimitedChunks)
				let previousChunks = quoteDelimitedChunks[advancedOffset]
				let chunkBeforeComment = chunk[..<range.lowerBound]
				return (previousChunks + [chunkBeforeComment])
					.joined(separator: quote) // readd the quotes that were removed in the initial split
			}
		}
		return self
	}
}
