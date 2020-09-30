import Foundation
import ReactiveSwift
import Result

/// Loads a bundle directory from a given URL and sends Bundle objects for each framework in it.
///
/// If `url` is an XCFramework, sends a Bundle for each embedded framework bundle.
/// If `url` is a framework bundle, sends a Bundle instance for the directory.
public func frameworkBundlesInURL(_ url: URL) -> SignalProducer<Bundle, DecodingError> {
	guard let bundle = Bundle(url: url) else {
		return .empty
	}

	switch bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String {
	case "FMWK":
		return SignalProducer(value: bundle)
	case "XFWK":
		let decoder = PropertyListDecoder()
		let infoData = bundle.infoDictionary.flatMap({ try? PropertyListSerialization.data(fromPropertyList: $0, format: .binary, options: 0) }) ?? Data()
		let xcframework = Result<XCFramework, DecodingError>(catching: { try decoder.decode(XCFramework.self, from: infoData) })
		return SignalProducer(result: xcframework)
			.map({ $0.availableLibraries }).flatten()
			.map({ Bundle(url: url.appendingPathComponent($0.identifier).appendingPathComponent($0.path)) })
			.skipNil()
	default:
		return .empty
	}
}

struct XCFramework: Decodable {
	let availableLibraries: [Library]
	let version: String

	struct Library: Decodable {
		let identifier: String
		let path: String

		enum CodingKeys: String, CodingKey {
			case identifier = "LibraryIdentifier"
			case path = "LibraryPath"
		}
	}

	enum CodingKeys: String, CodingKey {
		case availableLibraries = "AvailableLibraries"
		case version = "XCFrameworkFormatVersion"
	}
}
