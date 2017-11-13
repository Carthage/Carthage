import Foundation

/// Error parsing a binary-only framework JSON file, used in CarthageError.invalidBinaryJSON.
public enum BinaryJSONError: Error {
	/// Unable to parse the JSON.
	case invalidJSON(NSError)

	/// Unable to parse a semantic version from a framework entry.
	case invalidVersion(ScannableError)

	/// Unable to parse a URL from a framework entry.
	case invalidURL(String)

	/// URL is non-HTTPS
	case nonHTTPSURL(URL)
}

extension BinaryJSONError: CustomStringConvertible {
	public var description: String {
		switch self {
		case let .invalidJSON(error):
			return "invalid JSON: \(error)"

		case let .invalidVersion(error):
			return "unable to parse semantic version: \(error)"

		case let .invalidURL(string):
			return "invalid URL: \(string)"

		case let .nonHTTPSURL(url):
			return "specified URL '\(url)' must be HTTPS"
		}
	}
}

extension BinaryJSONError: Equatable {
	public static func == (lhs: BinaryJSONError, rhs: BinaryJSONError) -> Bool {
		switch (lhs, rhs) {
		case let (.invalidJSON(left), .invalidJSON(right)):
			return left == right

		case let (.invalidVersion(left), .invalidVersion(right)):
			return left == right

		case let (.invalidURL(left), .invalidURL(right)):
			return left == right

		case let (.nonHTTPSURL(left), .nonHTTPSURL(right)):
			return left == right

		default:
			return false
		}
	}
}
