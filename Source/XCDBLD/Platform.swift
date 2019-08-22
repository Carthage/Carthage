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
    
    /// UIKit for Mac
    case macCatalyst = "macCatalyst"

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
            
        case .macCatalyst:
            return [ .macCatalyst ]
		}
	}
    
    public var realPlatform: Platform {
        switch self {
        case .macCatalyst:
            return .iOS
            
        default:
            return self
        }
    }
}
