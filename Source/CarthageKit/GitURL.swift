import Foundation

/// Represents a URL for a Git remote.
public struct GitURL {
	/// The string representation of the URL.
	public let urlString: String
	internal let normalizedURLString: String
	private let hash: Int

	/// A normalized URL string, without protocol, authentication, or port
	/// information. This is mostly useful for comparison, and not for any
	/// actual Git operations.
	private static func normalizedURLString(from urlString: String) -> String {
		if let parsedURL = URL(string: urlString), let host = parsedURL.host {
			// Normal, valid URL.
			let path = strippingGitSuffix(parsedURL.path)
			return "\(host)\(path)"
		} else if urlString.hasPrefix("/") // "/path/to/..."
			|| urlString.hasPrefix(".") // "./path/to/...", "../path/to/..."
			|| urlString.hasPrefix("~") // "~/path/to/..."
			|| !urlString.contains(":") // "path/to/..." with avoiding "git@github.com:owner/name"
		{
			// Local path.
			return strippingGitSuffix(urlString)
		} else {
			// scp syntax.
			var strippedURLString = urlString

			if let index = strippedURLString.index(of: "@") {
				strippedURLString.removeSubrange(strippedURLString.startIndex...index)
			}

			var host = ""
			if let index = strippedURLString.index(of: ":") {
				host = String(strippedURLString[strippedURLString.startIndex..<index])
				strippedURLString.removeSubrange(strippedURLString.startIndex...index)
			}

			var path = strippingGitSuffix(strippedURLString)
			if !path.hasPrefix("/") {
				// This probably isn't strictly legit, but we'll have a forward
				// slash for other URL types.
				path.insert("/", at: path.startIndex)
			}

			return "\(host)\(path)"
		}
	}

	/// The name of the repository, if it can be inferred from the URL.
	public var name: String? {
		let components = urlString.split(omittingEmptySubsequences: true) { $0 == "/" }

		return components
			.last
			.map(String.init)
			.map(strippingGitSuffix)
	}

	public init(_ urlString: String) {
		self.urlString = urlString

		// Pre-compute the normalizedURL and hash for faster cache lookups
		self.normalizedURLString = GitURL.normalizedURLString(from: urlString)
		self.hash = normalizedURLString.hashValue
	}
}

extension GitURL: Equatable {
	public static func == (_ lhs: GitURL, _ rhs: GitURL) -> Bool {
		return lhs.normalizedURLString == rhs.normalizedURLString
	}
}

extension GitURL: Hashable {
	public var hashValue: Int {
		return hash
	}
}

extension GitURL: CustomStringConvertible {
	public var description: String {
		return urlString
	}
}
