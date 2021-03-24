import Foundation
import Result
import Tentacle

/// A struct including all constants.
public struct Constants {
	/// Carthage's bundle identifier.
	public static let bundleIdentifier: String = "org.carthage.CarthageKit"

	/// The name of the folder into which Carthage puts checked out dependencies (relative
	/// to the working directory).
	public static let checkoutsFolderPath = "Carthage/Checkouts"

	/// The name of the folder into which Carthage puts binaries it builds (relative
	/// to the working directory).
	public static let binariesFolderPath = "Carthage/Build"

	/// The fallback dependencies URL to be used in case
	/// the intended ~/Library/Caches/org.carthage.CarthageKit cannot
	/// be found or created.
	private static let fallbackDependenciesURL: URL = {
		let homePath: String
		if let homeEnvValue = ProcessInfo.processInfo.environment["HOME"] {
			homePath = (homeEnvValue as NSString).appendingPathComponent(".carthage")
		} else {
			homePath = ("~/.carthage" as NSString).expandingTildeInPath
		}
		return URL(fileURLWithPath: homePath, isDirectory: true)
	}()

	/// ~/Library/Caches/org.carthage.CarthageKit/
	private static let userCachesURL: URL = {
		let fileManager = FileManager.default

		let urlResult: Result<URL, NSError> = Result(catching: {
			try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
		}).flatMap { cachesURL in
			let dependenciesURL = cachesURL.appendingPathComponent(Constants.bundleIdentifier, isDirectory: true)
			let dependenciesPath = dependenciesURL.absoluteString

			if fileManager.fileExists(atPath: dependenciesPath, isDirectory: nil) {
				if fileManager.isWritableFile(atPath: dependenciesPath) {
					return Result(value: dependenciesURL)
				} else {
					let error = NSError(domain: Constants.bundleIdentifier, code: 0, userInfo: nil)
					return Result(error: error)
				}
			} else {
				return Result(catching: {
					try fileManager.createDirectory(
						at: dependenciesURL,
						withIntermediateDirectories: true,
						attributes: [FileAttributeKey.posixPermissions: 0o755]
					)
					return dependenciesURL
				})
			}
		}

		switch urlResult {
		case let .success(url):
			_ = try? FileManager.default.removeItem(at: Constants.fallbackDependenciesURL)
			return url

		case let .failure(error):
			NSLog("Warning: No Caches directory could be found or created: \(error.localizedDescription). (\(error))")
			return Constants.fallbackDependenciesURL
		}
	}()

	public struct Dependency {
		/// The file URL to the directory in which downloaded release binaries will be
		/// stored.
		///
		/// ~/Library/Caches/org.carthage.CarthageKit/binaries/
		public static var assetsURL: URL = Constants.userCachesURL.appendingPathComponent("binaries", isDirectory: true)

		/// The file URL to the directory in which cloned dependencies will be stored.
		///
		/// ~/Library/Caches/org.carthage.CarthageKit/dependencies/
		public static var repositoriesURL: URL = Constants.userCachesURL.appendingPathComponent("dependencies", isDirectory: true)

		/// The file URL to the directory in which per-dependency derived data
		/// directories will be stored.
		///
		/// ~/Library/Caches/org.carthage.CarthageKit/DerivedData/
		public static var derivedDataURL: URL = Constants.userCachesURL.appendingPathComponent("DerivedData", isDirectory: true)
	}

	public struct Project {
		/// The relative path to a project's Cartfile.
		public static let cartfilePath = "Cartfile"

		/// The relative path to a project's Cartfile.private.
		public static let privateCartfilePath = "Cartfile.private"

		/// The relative path to a project's Cartfile.resolved.
		public static let resolvedCartfilePath = "Cartfile.resolved"

		// TODO: Deprecate this.
		/// The text that needs to exist in a GitHub Release asset's name, for it to be
		/// tried as a binary framework.
		public static let frameworkBinaryAssetPattern = ".framework"
		public static let xcframeworkBinaryAssetPattern = ".xcframework"

		/// MIME types allowed for GitHub Release assets, for them to be considered as
		/// binary frameworks.
		public static let binaryAssetContentTypes = ["application/zip", "application/x-zip-compressed", "application/octet-stream"]
	}
}

public func binaryAssetPrioritizingReducer(_ asset: Release.Asset) -> (keyName: String, asset: Release.Asset, priority: UInt8)? {
	guard Constants.Project.binaryAssetContentTypes.contains(asset.contentType) else { return nil }

	let priorities: KeyValuePairs = [".xcframework": 10 as UInt8, ".XCFramework": 10, ".XCframework": 10, ".framework": 40]

	return (priorities.lazy.compactMap {
		var (potentialPatternRange, keyName) = (asset.name.range(of: $0), asset.name)
		guard let patternRange = potentialPatternRange else { return nil }
		keyName.removeSubrange(patternRange)
		return (keyName, asset, $1)
	} as LazyMapSequence).first
}
