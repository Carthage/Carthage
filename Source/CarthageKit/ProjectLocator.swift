import Foundation
#if swift(>=3)
import ReactiveSwift
#else
import ReactiveCocoa
#endif

/// Describes how to locate the actual project or workspace that Xcode should
/// build.
public enum ProjectLocator: Comparable {
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
		return fileURL.carthage_pathComponents.count - 1
	}

	/// Attempts to locate projects and workspaces within the given directory.
	///
	/// Sends all matches in preferential order.
	public static func locate(in directoryURL: URL) -> SignalProducer<ProjectLocator, CarthageError> {
		let enumerationOptions: FileManager.DirectoryEnumerationOptions = [ .skipsHiddenFiles, .skipsPackageDescendants ]

		return gitmodulesEntriesInRepository(directoryURL, revision: nil)
			.map { directoryURL.appendingPathComponent($0.path) }
			.concat(value: directoryURL.appendingPathComponent(CarthageProjectCheckoutsPath))
			.collect()
			.flatMap(.merge) { directoriesToSkip in
				return FileManager.`default`
					.carthage_enumerator(at: directoryURL.resolvingSymlinksInPath(), includingPropertiesForKeys: [ .typeIdentifierKey ], options: enumerationOptions, catchErrors: true)
					.map { _, url in url }
					.filter { url in
						return !directoriesToSkip.contains { $0.hasSubdirectory(url) }
					}
			}
			.map { url -> ProjectLocator? in
				if let uti = url.typeIdentifier.value {
					if (UTTypeConformsTo(uti as CFString, "com.apple.dt.document.workspace" as CFString)) {
						return .workspace(url)
					} else if (UTTypeConformsTo(uti as CFString, "com.apple.xcode.project" as CFString)) {
						return .projectFile(url)
					}
				}
				return nil
			}
			.skipNil()
			.collect()
			.map { $0.sorted() }
			.flatMap(.merge) { SignalProducer<ProjectLocator, CarthageError>($0) }
	}

	/// Sends each scheme found in the receiver.
	public func schemes() -> SignalProducer<String, CarthageError> {
		let task = xcodebuildTask("-list", BuildArguments(project: self))

		return task.launch()
			.ignoreTaskData()
			.mapError(CarthageError.taskError)
			// xcodebuild has a bug where xcodebuild -list can sometimes hang
			// indefinitely on projects that don't share any schemes, so
			// automatically bail out if it looks like that's happening.
			.timeout(after: 60, raising: .xcodebuildTimeout(self), on: QueueScheduler(qos: QOS_CLASS_DEFAULT))
			.retry(upTo: 2)
			.map { data in
				return String(data: data, encoding: .utf8)!
			}
			.flatMap(.merge) { string in
				return string.linesProducer
			}
			.flatMap(.merge) { line -> SignalProducer<String, CarthageError> in
				// Matches one of these two possible messages:
				//
				// '    This project contains no schemes.'
				// 'There are no schemes in workspace "Carthage".'
				if line.hasSuffix("contains no schemes.") || line.hasPrefix("There are no schemes") {
					return SignalProducer(error: .noSharedSchemes(self, nil))
				} else {
					return SignalProducer(value: line)
				}
			}
			.skip { line in !line.hasSuffix("Schemes:") }
			.skip(first: 1)
			.take { line in !line.isEmpty }
			.map { line in line.trimmingCharacters(in: .whitespaces) }
	}
}

public func ==(_ lhs: ProjectLocator, _ rhs: ProjectLocator) -> Bool {
	switch (lhs, rhs) {
	case let (.workspace(left), .workspace(right)):
		return left == right

	case let (.projectFile(left), .projectFile(right)):
		return left == right

	default:
		return false
	}
}

public func <(_ lhs: ProjectLocator, _ rhs: ProjectLocator) -> Bool {
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
		return lhs.fileURL.carthage_path.characters.lexicographicalCompare(rhs.fileURL.carthage_path.characters)
	}
}

extension ProjectLocator: CustomStringConvertible {
	public var description: String {
		return fileURL.carthage_lastPathComponent
	}
}
