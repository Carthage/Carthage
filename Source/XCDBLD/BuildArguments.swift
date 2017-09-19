import Foundation

/// Configures a build with Xcode.
public struct BuildArguments {
	/// Available actions for xcodebuild listed in `man xcodebuild`
	public enum Action: String {
		case build = "build"
		case buildForTesting = "build-for-testing"
		case analyze = "analyze"
		case archive = "archive"
		case test = "test"
		case testWithoutBuilding = "test-without-building"
		case installSrc = "install-src"
		case install = "install"
		case clean = "clean"
	}

	/// Represents a build setting whether full bitcode should be embedded in the
	/// binary.
	public enum BitcodeGenerationMode: String {
		/// Only bitcode marker will be embedded.
		case marker = "marker"

		/// Full bitcode will be embedded.
		case bitcode = "bitcode"
	}

	/// The project to build.
	public let project: ProjectLocator

	/// The scheme to build in the project.
	public var scheme: Scheme?

	/// The configuration to use when building the project.
	public var configuration: String?

	/// The path to the derived data.
	public var derivedDataPath: String?

	/// The platform SDK to build for.
	public var sdk: SDK?

	/// The Swift toolchain to use.
	public var toolchain: String?

	/// The run destination to try building for.
	public var destination: String?

	/// The amount of time xcodebuild spends searching for the destination (in seconds).
	public var destinationTimeout: UInt?

	/// The build setting whether the product includes only object code for
	/// the native architecture.
	public var onlyActiveArchitecture: Bool?

	/// The build setting whether full bitcode should be embedded in the binary.
	public var bitcodeGenerationMode: BitcodeGenerationMode?

	public init(
		project: ProjectLocator,
		scheme: Scheme? = nil,
		configuration: String? = nil,
		derivedDataPath: String? = nil,
		sdk: SDK? = nil,
		toolchain: String? = nil
	) {
		self.project = project
		self.scheme = scheme
		self.configuration = configuration
		self.derivedDataPath = derivedDataPath
		self.sdk = sdk
		self.toolchain = toolchain
	}

	/// The `xcodebuild` invocation corresponding to the receiver.
	public var arguments: [String] {
		var args = [ "xcodebuild" ]

		switch project {
		case let .workspace(url):
			args += [ "-workspace", url.path ]

		case let .projectFile(url):
			args += [ "-project", url.path ]
		}

		if let scheme = scheme {
			args += [ "-scheme", scheme.name ]
		}

		if let configuration = configuration {
			args += [ "-configuration", configuration ]
		}

		if let derivedDataPath = derivedDataPath {
			let standarizedPath = URL(fileURLWithPath: (derivedDataPath as NSString).expandingTildeInPath).standardizedFileURL.path
			if !derivedDataPath.isEmpty && !standarizedPath.isEmpty {
				args += [ "-derivedDataPath", standarizedPath ]
			}
		}

		if let sdk = sdk {
			// Passing in -sdk macosx appears to break implicit dependency
			// resolution (see Carthage/Carthage#347).
			//
			// Since we wouldn't be trying to build this target unless it were
			// for macOS already, just let xcodebuild figure out the SDK on its
			// own.
			if sdk != .macOSX {
				args += [ "-sdk", sdk.rawValue ]
			}
		}

		if let toolchain = toolchain {
			args += [ "-toolchain", toolchain ]
		}

		if let destination = destination {
			args += [ "-destination", destination ]
		}

		if let destinationTimeout = destinationTimeout {
			args += [ "-destination-timeout", String(destinationTimeout) ]
		}

		if let onlyActiveArchitecture = onlyActiveArchitecture {
			if onlyActiveArchitecture {
				args += [ "ONLY_ACTIVE_ARCH=YES" ]
			} else {
				args += [ "ONLY_ACTIVE_ARCH=NO" ]
			}
		}

		if let bitcodeGenerationMode = bitcodeGenerationMode {
			args += [ "BITCODE_GENERATION_MODE=\(bitcodeGenerationMode.rawValue)" ]
		}

		// Disable code signing requirement for all builds
		// Frameworks get signed in the copy-frameworks action
		args += [ "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=" ]

		args += [ "CARTHAGE=YES" ]

		return args
	}
}

extension BuildArguments: CustomStringConvertible {
	public var description: String {
		return arguments.joined(separator: " ")
	}
}
