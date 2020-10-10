import Foundation
import ReactiveSwift
import Result

/// Loads a bundle directory from a given URL and sends Bundle objects for each framework in it.
///
/// If `url` is an XCFramework, sends a Bundle for each embedded framework bundle.
/// If `url` is a framework bundle, sends a Bundle instance for the directory.
/// - parameter url: A framework or xcframework URL to load from.
/// - parameter platformName: If given, only sends bundles from an XCFramework with a matching `SupportedPlatform`.
/// - parameter variant: If given along with `platformName`, only sends bundles from an XCFramework with a matching `SupportedPlatformVariant`.
public func frameworkBundlesInURL(_ url: URL, compatibleWith platformName: String? = nil, variant: String? = nil) -> SignalProducer<Bundle, DecodingError> {
	guard let bundle = Bundle(url: url) else {
		return .empty
	}

	switch bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String {
	case "XFWK":
		let decoder = PropertyListDecoder()
		let infoData = bundle.infoDictionary.flatMap({ try? PropertyListSerialization.data(fromPropertyList: $0, format: .binary, options: 0) }) ?? Data()
		let xcframework = Result<XCFramework, DecodingError>(catching: { try decoder.decode(XCFramework.self, from: infoData) })
		return SignalProducer(result: xcframework)
			.map({ $0.availableLibraries }).flatten()
			.filter { library in
				guard let platformName = platformName else { return true }
				return library.supportedPlatform == platformName && library.supportedPlatformVariant == variant
			}
			.map({ Bundle(url: url.appendingPathComponent($0.identifier).appendingPathComponent($0.path)) })
			.skipNil()
	default: // Typically "FMWK" but not required
		return SignalProducer(value: bundle)
	}
}

struct XCFramework: Decodable {
	let availableLibraries: [Library]
	let version: String

	struct Library: Decodable {
		let identifier: String
		let path: String
		let supportedPlatform: String
		let supportedPlatformVariant: String?

		enum CodingKeys: String, CodingKey {
			case identifier = "LibraryIdentifier"
			case path = "LibraryPath"
			case supportedPlatform = "SupportedPlatform"
			case supportedPlatformVariant = "SupportedPlatformVariant"
		}
	}

	enum CodingKeys: String, CodingKey {
		case availableLibraries = "AvailableLibraries"
		case version = "XCFrameworkFormatVersion"
	}
}
