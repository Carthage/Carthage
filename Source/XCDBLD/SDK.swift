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

	public static let allSDKs: Set<SDK> = [.macOSX, .iPhoneOS, .iPhoneSimulator, .watchOS, .watchSimulator, .tvOS, .tvSimulator]

	/// Returns whether this is a device SDK.
	public var isDevice: Bool {
		switch self {
		case .macOSX, .iPhoneOS, .watchOS, .tvOS:
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

		case .macOSX, .iPhoneOS, .watchOS, .tvOS:
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
		}
	}
}

// TODO: this won't be necessary anymore in Swift 2.
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
		}
	}
}
