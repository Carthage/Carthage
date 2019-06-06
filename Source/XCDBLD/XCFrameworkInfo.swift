import Foundation

public enum XCFrameworkPlatformVariant: String {
	case simulator
}

public struct XCFrameworkLibrary {

	public let identifier: String
	public let path: String
	public let supportedArchitectures: [String]
	public let supportedPlatform: Platform
	public let supportedSDK: SDK

	public init?(_ dictionary: [String: Any]) {

		guard let identifier = dictionary["LibraryIdentifier"] as? String,
			let path = dictionary["LibraryPath"] as? String,
			let supportedArchs = dictionary["SupportedArchitectures"] as? [String],
			let supportPlatform = dictionary["SupportedPlatform"] as? String else {
				return nil
		}

		let supportedPlatformVariant = dictionary["SupportedPlatformVariant"] as? XCFrameworkPlatformVariant
		guard let supportedPlatform = Platform(platform: supportPlatform),
			let sdk = SDK(platform: supportedPlatform, variant: supportedPlatformVariant) else {
				return nil
		}

		self.identifier = identifier
		self.path = path
		self.supportedArchitectures = supportedArchs
		self.supportedPlatform = supportedPlatform
		self.supportedSDK = sdk
	}
}

fileprivate extension Platform {

	static var aliases: [String : Platform] {
		["ios" : .iOS,
		 "macos" : .macOS,
		 "watchos" : .watchOS,
		 "tvos" : .tvOS
		]
	}

	init?(platform: String) {

		guard let vanillaPlatform = Platform(rawValue: platform) else {
			guard let aliasedPlatfrom = Platform.aliases[platform] else {
				return nil
			}
			self = aliasedPlatfrom
			return
		}
		self = vanillaPlatform
	}
}

fileprivate extension SDK {

	init?(platform: Platform, variant: XCFrameworkPlatformVariant?) {

		let isSimulatorVariant = variant != nil && variant! == .simulator

		switch platform {
			case .iOS:
				self = isSimulatorVariant ? .iPhoneSimulator : .iPhoneOS
			case .macOS:
				guard !isSimulatorVariant else { return nil }
				self = .macOSX
			case .tvOS:
				self = isSimulatorVariant ? .tvSimulator : .tvOS
			case .watchOS:
				self = isSimulatorVariant ? .watchSimulator : .watchOS
		}
	}
}

/// Represents the information parsed from the Info.plist of an .xcframework bundle
public struct XCFrameworkInfo {

	public let formatVersion: String
	public let packageTypeString: String
	public let availableLibraries: [XCFrameworkLibrary]

	public init?(_ dictionary: [String: Any]) {

		guard let formatVersion = dictionary["XCFrameworkFormatVersion"] as? String,
			let packageType = dictionary["CFBundlePackageType"] as? String,
			let avalableLibraries = (dictionary["AvailableLibraries"] as? [[String : Any]])
				.flatMap({ libDicts in libDicts.compactMap(XCFrameworkLibrary.init) }) else {
				return nil
		}

		self.formatVersion = formatVersion
		self.packageTypeString = packageType
		self.availableLibraries = avalableLibraries
	}
}
