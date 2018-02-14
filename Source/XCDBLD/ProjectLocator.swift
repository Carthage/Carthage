import Foundation
import ReactiveSwift

// swiftlint:disable missing_docs

/// Describes how to locate the actual project or workspace that Xcode should
/// build.
public enum ProjectLocator {
	/// The `xcworkspace` at the given file URL should be built.
	case workspace(URL)

	/// The `xcodeproj` at the given file URL should be built.
	case projectFile(URL)

	/// The file URL this locator refers to.
	public var fileURL: URL {
		switch self {
		case let .workspace(url):
			assert(url.isFileURL)
			return url

		case let .projectFile(url):
			assert(url.isFileURL)
			return url
		}
	}

	/// The number of levels deep the current object is in the directory hierarchy.
	public var level: Int {
		return fileURL.pathComponents.count - 1
	}
}

extension ProjectLocator: Comparable {
	public static func == (_ lhs: ProjectLocator, _ rhs: ProjectLocator) -> Bool {
		switch (lhs, rhs) {
		case let (.workspace(left), .workspace(right)):
			return left == right

		case let (.projectFile(left), .projectFile(right)):
			return left == right

		default:
			return false
		}
	}

	public static func < (_ lhs: ProjectLocator, _ rhs: ProjectLocator) -> Bool {
		// Prefer top-level directories
		let leftLevel = lhs.level
		let rightLevel = rhs.level

		guard leftLevel == rightLevel else {
			return leftLevel < rightLevel
		}

		// Prefer workspaces over projects.
		switch (lhs, rhs) {
		case (.workspace, .projectFile):
			return true

		case (.projectFile, .workspace):
			return false

		default:
			return lhs.fileURL.path.lexicographicallyPrecedes(rhs.fileURL.path)
		}
	}
}

extension ProjectLocator: CustomStringConvertible {
	public var description: String {
		return fileURL.lastPathComponent
	}
}
