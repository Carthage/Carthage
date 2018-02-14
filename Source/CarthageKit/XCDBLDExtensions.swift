import Foundation
import ReactiveSwift
import ReactiveTask
import Result
import XCDBLD

extension MachOType {
	/// Attempts to parse a Mach-O type from a string returned from `xcodebuild`.
	public static func from(string: String) -> Result<MachOType, CarthageError> {
		return Result(self.init(rawValue: string), failWith: .parseError(description: "unexpected Mach-O type \"\(string)\""))
	}
}

extension Platform {
	/// The relative path at which binaries corresponding to this platform will
	/// be stored.
	public var relativePath: String {
		let subfolderName = rawValue
		return (Constants.binariesFolderPath as NSString).appendingPathComponent(subfolderName)
	}
}

extension ProjectLocator {
	/// Attempts to locate projects and workspaces within the given directory.
	///
	/// Sends all matches in preferential order.
	public static func locate(in directoryURL: URL) -> SignalProducer<ProjectLocator, CarthageError> {
		let enumerationOptions: FileManager.DirectoryEnumerationOptions = [ .skipsHiddenFiles, .skipsPackageDescendants ]

		return gitmodulesEntriesInRepository(directoryURL, revision: nil)
			.map { directoryURL.appendingPathComponent($0.path) }
			.concat(value: directoryURL.appendingPathComponent(carthageProjectCheckoutsPath))
			.collect()
			.flatMap(.merge) { directoriesToSkip -> SignalProducer<URL, CarthageError> in
				return FileManager.default.reactive
					.enumerator(at: directoryURL.resolvingSymlinksInPath(), includingPropertiesForKeys: [ .typeIdentifierKey ], options: enumerationOptions, catchErrors: true)
					.map { _, url in url }
					.filter { url in
						return !directoriesToSkip.contains { $0.hasSubdirectory(url) }
					}
			}
			.filterMap { url -> ProjectLocator? in
				if let uti = url.typeIdentifier.value {
					if (UTTypeConformsTo(uti as CFString, "com.apple.dt.document.workspace" as CFString)) {
						return .workspace(url)
					} else if (UTTypeConformsTo(uti as CFString, "com.apple.xcode.project" as CFString)) {
						return .projectFile(url)
					}
				}
				return nil
			}
			.collect()
			.map { $0.sorted() }
			.flatMap(.merge) { SignalProducer<ProjectLocator, CarthageError>($0) }
	}

	/// Sends each scheme found in the receiver.
	public func schemes() -> SignalProducer<Scheme, CarthageError> {
		let task = xcodebuildTask("-list", BuildArguments(project: self))

		return task.launch()
			.ignoreTaskData()
			.mapError(CarthageError.taskError)
			// xcodebuild has a bug where xcodebuild -list can sometimes hang
			// indefinitely on projects that don't share any schemes, so
			// automatically bail out if it looks like that's happening.
			.timeout(after: 60, raising: .xcodebuildTimeout(self), on: QueueScheduler())
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
			.map { line in
				let trimmed = line.trimmingCharacters(in: .whitespaces)
				return Scheme(trimmed)
			}
	}
}

extension SDK {
	/// Attempts to parse an SDK name from a string returned from `xcodebuild`.
	public static func from(string: String) -> Result<SDK, CarthageError> {
		return Result(self.init(rawValue: string.lowercased()), failWith: .parseError(description: "unexpected SDK key \"\(string)\""))
	}

	/// Split the given SDKs into simulator ones and device ones.
	internal static func splitSDKs<S: Sequence>(_ sdks: S) -> (simulators: [SDK], devices: [SDK]) where S.Iterator.Element == SDK {
		return (
			simulators: sdks.filter { $0.isSimulator },
			devices: sdks.filter { !$0.isSimulator }
		)
	}
}
