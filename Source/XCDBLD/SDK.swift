import Foundation
import Result

/// Represents an SDK buildable by Xcode.
public enum SDK: String {
	/// macOS.
	case macOSX = "macosx"

	/// iOS, for device.
	case iPhoneOS = "iphoneos"

	/// iOS, for the simulator.
	case iPhoneSimulator = "iphonesimulator"

	/// watchOS, for the Apple Watch device.
	case watchOS = "watchos"

	/// watchSimulator, for the Apple Watch simulator.
	case watchSimulator = "watchsimulator"

	/// tvOS, for the Apple TV device.
	case tvOS = "appletvos"

	/// tvSimulator, for the Apple TV simulator.
	case tvSimulator = "appletvsimulator"
    
    /// UIKit for Mac, builds as iPhoneOS
    case macCatalyst = "maccatalyst"

    public static let allSDKs: Set<SDK> = [.macOSX, .iPhoneOS, .iPhoneSimulator, .watchOS, .watchSimulator, .tvOS, .tvSimulator, .macCatalyst]

	/// Returns whether this is a device SDK.
	public var isDevice: Bool {
		switch self {
        case .macOSX, .iPhoneOS, .watchOS, .tvOS, .macCatalyst:
			return true

		case .iPhoneSimulator, .watchSimulator, .tvSimulator:
			return false
		}
	}

	/// Returns whether this is a simulator SDK.
	public var isSimulator: Bool {
		switch self {
		case .iPhoneSimulator, .watchSimulator, .tvSimulator:
			return true

        case .macOSX, .iPhoneOS, .watchOS, .tvOS, .macCatalyst:
			return false
		}
	}

	/// The platform that this SDK targets.
	public var platform: Platform {
		switch self {
		case .iPhoneOS, .iPhoneSimulator:
			return .iOS

		case .watchOS, .watchSimulator:
			return .watchOS

		case .tvOS, .tvSimulator:
			return .tvOS

		case .macOSX:
			return .macOS
            
        case .macCatalyst:
            return .macCatalyst
		}
	}
    
    /// The real SDK to use when building
    public var realSDK: SDK {
        switch self {
        case .macCatalyst:
            return .iPhoneOS
            
        default:
            return self
        }
    }
    
    /// Any additional build options to use when building
    public var additionalBuildOptions: [String] {
        switch self {
        case .macCatalyst:
            return [
                "-destination",
                "platform=macOS,arch=x86_64,variant=Mac Catalyst",
                "IS_MACCATALYST=YES",
                "IS_UIKITFORMAC=YES",
                "SUPPORTS_MACCATALYST=YES",
            ]
        default:
            return []
        }
    }

	private static var aliases: [String: SDK] {
		return ["tvos": .tvOS]
	}

	public init?(rawValue: String) {
		let lowerCasedRawValue = rawValue.lowercased()
		let maybeSDK = SDK
			.allSDKs
			.map { ($0, $0.rawValue) }
			.first { _, stringValue in stringValue.lowercased() == lowerCasedRawValue }?
			.0

		guard let sdk = maybeSDK ?? SDK.aliases[lowerCasedRawValue] else {
			return nil
		}
		self = sdk
	}
}

extension SDK: CustomStringConvertible {
	public var description: String {
		switch self {
		case .iPhoneOS:
			return "iOS Device"

		case .iPhoneSimulator:
			return "iOS Simulator"

		case .macOSX:
			return "macOS"

		case .watchOS:
			return "watchOS"

		case .watchSimulator:
			return "watchOS Simulator"

		case .tvOS:
			return "tvOS"

		case .tvSimulator:
			return "tvOS Simulator"
            
        case .macCatalyst:
            return "macCatalyst"
		}
	}
}
