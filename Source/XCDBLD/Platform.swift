import Foundation

/// Represents a platform to build for.
public enum Platform: String {
	/// macOS.
	case macOS = "Mac"

	/// iOS for device and simulator.
	case iOS = "iOS"

	/// Apple Watch device and simulator.
	case watchOS = "watchOS"

	/// Apple TV device and simulator.
	case tvOS = "tvOS"

	/// All supported build platforms.
	public static let supportedPlatforms: [Platform] = [ .macOS, .iOS, .watchOS, .tvOS ]

	/// The SDKs that need to be built for this platform.
	public var SDKs: [SDK] {
		switch self {
		case .macOS:
			return [ .macOSX ]

		case .iOS:
			return [ .iPhoneSimulator, .iPhoneOS ]

		case .watchOS:
			return [ .watchOS, .watchSimulator ]

		case .tvOS:
			return [ .tvOS, .tvSimulator ]
		}
	}
}

// TODO: this won't be necessary anymore with Swift 2.
extension Platform: CustomStringConvertible {
	public var description: String {
		return rawValue
	}
}
