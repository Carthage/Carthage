import Foundation
import Result

/// The relative path to a project's checked out dependencies.
public let carthageProjectCheckoutsPath = "Carthage/Checkouts"

/// Represents a Cartfile, which is a specification of a project's dependencies
/// and any other settings Carthage needs to build it.
public struct Cartfile {
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

		let commentIndicator = "#"
		string.enumerateLines { line, stop in
			let scanner = Scanner(string: line)

			if scanner.scanString(commentIndicator, into: nil) {
				// Skip the rest of the line.
				return
			}

			if scanner.isAtEnd {
				// The line was all whitespace.
				return
			}

			switch Dependency.from(scanner).fanout(VersionSpecifier.from(scanner)) {
			case let .success((dependency, version)):
				if case .binary = dependency, case .gitReference = version {
					result = .failure(
						CarthageError.parseError(
							description: "binary dependencies cannot have a git reference for the version specifier in line: \(scanner.currentLine)"
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

			if scanner.scanString(commentIndicator, into: nil) {
				// Skip the rest of the line.
				return
			}

			if !scanner.isAtEnd {
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
