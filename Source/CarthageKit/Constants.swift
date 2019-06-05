import Foundation
import Result

/// A struct including all constants.
public struct Constants {
	/// Carthage's bundle identifier.
	public static let bundleIdentifier: String = "org.carthage.CarthageKit"
    
	/// The name of the folder into which Carthage puts binaries it builds (relative
	/// to the working directory).
    public static internal(set) var binariesFolderPath = "Carthage/Build"
    
    /// The relative path to a project's checked out dependencies.
    public static internal(set) var carthageProjectCheckoutsPath = "Carthage/Checkouts"
    
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
        
        public static func configure(with custom: String) {
            guard !custom.isEmpty else { return }
            guard custom.lowercased() != "private" && custom.lowercased() != "resolved" && !custom.contains(".") else {
                fatalError("Invalid custom value: \(custom)")
            }
            
            cartfilePath = "Cartfile\(custom)"
            privateCartfilePath = "Cartfile\(custom).private"
            resolvedCartfilePath = "Cartfile\(custom).resolved"
            
            Constants.binariesFolderPath = "Carthage\(custom)/Build"
            Constants.carthageProjectCheckoutsPath = "Carthage\(custom)/Checkouts"
            
            self.custom = custom
        }
        
        /// The relative path to a project's Cartfile.
        public static private(set) var cartfilePath = "Cartfile"
        
        /// The relative path to a project's Cartfile.private.
        public static private(set) var privateCartfilePath = "Cartfile.private"
        
        /// The relative path to a project's Cartfile.resolved.
        public static private(set) var resolvedCartfilePath = "Cartfile.resolved"
        
        /// Custom suffix
        public static private(set) var custom: String?

		/// The text that needs to exist in a GitHub Release asset's name, for it to be
		/// tried as a binary framework.
		public static let binaryAssetPattern = ".framework"

		/// MIME types allowed for GitHub Release assets, for them to be considered as
		/// binary frameworks.
		public static let binaryAssetContentTypes = ["application/zip", "application/octet-stream"]
	}
}
