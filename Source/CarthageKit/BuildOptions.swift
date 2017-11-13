import XCDBLD

/// The build options used for building `xcodebuild` command.
public struct BuildOptions {
	/// The Xcode configuration to build.
	public var configuration: String
	/// The platforms to build for.
	public var platforms: Set<Platform>
	/// The toolchain to build with.
	public var toolchain: String?
	/// The path to the custom derived data folder.
	public var derivedDataPath: String?
	/// Rebuild even if cached builds exist.
	public var cacheBuilds: Bool

	public init(configuration: String, platforms: Set<Platform> = [], toolchain: String? = nil, derivedDataPath: String? = nil, cacheBuilds: Bool = true) {
		self.configuration = configuration
		self.platforms = platforms
		self.toolchain = toolchain
		self.derivedDataPath = derivedDataPath
		self.cacheBuilds = cacheBuilds
	}
}
