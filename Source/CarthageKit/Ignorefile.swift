import Foundation
import Result

/// Represents a Cartfile.ignore, which is a specification of what projects
/// and schemes should be ignored and therefore excluded from update/boostrap.
public struct Ignorefile {
	/// The ignore entries listed in the Cartfile.ignore.
	public var ignoreEntries: [IgnoreEntry]

	/// Returns the location where Cartfile.ignore should exist within the
	/// given directory.
	public static func url(in directoryURL: URL) -> URL {
		return directoryURL.appendingPathComponent("Cartfile.ignore")
	}

	/// Attempts to parse Cartfile.ignore information from a string.
	public static func from(string: String) -> Result<Ignorefile, CarthageError> {
		var ignoreEntries: [IgnoreEntry] = []
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

			switch IgnoreEntry.from(scanner) {
			case let .success(ignoreEntry):
				ignoreEntries.append(ignoreEntry)

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
			return .success(Ignorefile(ignoreEntries: ignoreEntries))
		}
	}

	/// Attempts to parse a Ignorefile from a file at a given URL.
	public static func from(file ignorefileURL: URL) -> Result<Ignorefile, CarthageError> {
		do {
			let ignorefileContents = try String(contentsOf: ignorefileURL, encoding: .utf8)
			return Ignorefile
				.from(string: ignorefileContents)
		} catch let error as NSError {
			return .failure(CarthageError.readFailed(ignorefileURL, error))
		}
	}
}

/// Uniquely identifies an ignore entry that can be used for ignores.
public struct IgnoreEntry {
	public let project: String?
	public let scheme: String

	public init(project: String?, scheme: String) {
		self.project = project
		self.scheme = scheme
	}
}

extension IgnoreEntry: Comparable {
	public static func == (_ lhs: IgnoreEntry, _ rhs: IgnoreEntry) -> Bool {
		return lhs.project == rhs.project && lhs.scheme == rhs.scheme
	}

	public static func < (_ lhs: IgnoreEntry, _ rhs: IgnoreEntry) -> Bool {
		guard let leftProject = lhs.project, let rightProject = rhs.project else {
			return lhs.scheme < rhs.scheme
		}

		return leftProject < rightProject && lhs.scheme < rhs.scheme
	}
}

extension IgnoreEntry: Hashable {
	public var hashValue: Int {
		guard let project = project else {
			return scheme.hashValue
		}

		return project.hashValue ^ scheme.hashValue
	}
}

extension IgnoreEntry: Scannable {
	/// Attempts to parse an IgnoreEntry.
	public static func from(_ scanner: Scanner) -> Result<IgnoreEntry, ScannableError> {
		let parser: (String) -> Result<IgnoreEntry, ScannableError>

		if scanner.scanString("scheme", into: nil) {
			parser = { name in
				let ignoreEntry: IgnoreEntry = {
					let nameComponents = name.components(separatedBy: "/")
					if nameComponents.count == 1 {
						return IgnoreEntry(project: nil, scheme: nameComponents[0])
					} else {
						return IgnoreEntry(project: nameComponents.first!, scheme: nameComponents.last!)
					}
				}()

				return .success(ignoreEntry)
			}
		} else {
			return .failure(ScannableError(message: "unexpected ignore entry type", currentLine: scanner.currentLine))
		}

		if !scanner.scanString("\"", into: nil) {
			return .failure(ScannableError(message: "expected string after ignore entry type", currentLine: scanner.currentLine))
		}

		var name: NSString?
		if !scanner.scanUpTo("\"", into: &name) || !scanner.scanString("\"", into: nil) {
			return .failure(ScannableError(message: "empty or unterminated string after ignore entry type", currentLine: scanner.currentLine))
		}

		if let name = name {
			return parser(name as String)
		} else {
			return .failure(ScannableError(message: "empty string after dependency type", currentLine: scanner.currentLine))
		}
	}
}

extension IgnoreEntry: CustomStringConvertible {
	public var description: String {
		return "project \"\(String(describing: project))\", scheme \"\(scheme)\""
	}
}
