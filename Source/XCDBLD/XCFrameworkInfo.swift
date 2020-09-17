import Foundation

public enum XCFrameworkPlatformVariant: String {
	case simulator
}

public struct XCFrameworkLibrary {

	public let identifier: String
	public let path: String
	public let supportedArchitectures: [String]
	public let supportedPlatform: String
	public let supportedSDK: SDK

	public init?(_ dictionary: [String: Any]) {

		guard let identifier = dictionary["LibraryIdentifier"] as? String,
			let path = dictionary["LibraryPath"] as? String,
			let supportedArchs = dictionary["SupportedArchitectures"] as? [String],
			let supportedPlatform = dictionary["SupportedPlatform"] as? String else {
				return nil
		}

        let supportedPlatformVariant = (dictionary["SupportedPlatformVariant"] as? XCFrameworkPlatformVariant)?.rawValue

		self.identifier = identifier
		self.path = path
		self.supportedArchitectures = supportedArchs
		self.supportedPlatform = supportedPlatform
		self.supportedSDK =  SDK(name: supportedPlatform, simulatorHeuristic: supportedPlatformVariant ?? "")
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
