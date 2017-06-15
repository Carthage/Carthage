import Foundation
import Result

/// Represents a Cartfile.ignore, which is a specification of what projects
/// and schemes should be ignored and therefore excluded from update/boostrap.
public struct Ignorefile {
	/// The project names listed in the Cartfile.ignore.
	public var projects: [IgnoreEntry]

	/// The scheme names listed in the Cartfile.ignore.
	public var schemes: [IgnoreEntry]

	/// Returns the location where Cartfile.ignore should exist within the
	/// given directory.
	public static func url(in directoryURL: URL) -> URL {
		return directoryURL.appendingPathComponent("Cartfile.ignore")
	}

	/// Attempts to parse Cartfile.ignore information from a string.
	public static func from(string: String) -> Result<Ignorefile, CarthageError> {
		var projects: [IgnoreEntry] = []
		var schemes: [IgnoreEntry] = []
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
				switch ignoreEntry {
				case .project:
					projects.append(ignoreEntry)

				case .scheme:
					schemes.append(ignoreEntry)
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
			return .success(Ignorefile(projects: projects, schemes: schemes))
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
public enum IgnoreEntry {
	/// A project to be ignored.
	case project(String)

	/// A scheme to be ignored.
	case scheme(String)
}

extension IgnoreEntry: Comparable {
	public static func == (_ lhs: IgnoreEntry, _ rhs: IgnoreEntry) -> Bool {
		switch (lhs, rhs) {
		case let (.project(left), .project(right)), let (.scheme(left), .scheme(right)),
		     let (.project(left), .scheme(right)), let (.scheme(left), .project(right)):
			return left.caseInsensitiveCompare(right) == .orderedSame
		}
	}

	public static func < (_ lhs: IgnoreEntry, _ rhs: IgnoreEntry) -> Bool {
		switch (lhs, rhs) {
		case let (.project(left), .project(right)), let (.scheme(left), .scheme(right)),
		     let (.project(left), .scheme(right)), let (.scheme(left), .project(right)):
			return left.caseInsensitiveCompare(right) == .orderedAscending
		}
	}
}

extension IgnoreEntry: Hashable {
	public var hashValue: Int {
		switch self {
		case let .project(name), let .scheme(name):
			return name.hashValue
		}
	}
}

extension IgnoreEntry: Scannable {
	/// Attempts to parse an IgnoreEntry.
	public static func from(_ scanner: Scanner) -> Result<IgnoreEntry, ScannableError> {
		let parser: (String) -> Result<IgnoreEntry, ScannableError>

		if scanner.scanString("project", into: nil) {
			parser = { name in
				return .success(IgnoreEntry.project(name))
			}
		} else if scanner.scanString("scheme", into: nil) {
			parser = { name in
				return .success(IgnoreEntry.scheme(name))
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
		switch self {
		case let .project(name):
			return "project \"\(name)\""

		case let .scheme(name):
			return "scheme \"\(name)\""
		}
	}
}
