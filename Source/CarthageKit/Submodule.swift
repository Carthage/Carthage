/// A Git submodule.
public struct Submodule {
	/// The name of the submodule. Usually (but not always) the same as the
	/// path.
	public let name: String

	/// The relative path at which the submodule is checked out.
	public let path: String

	/// The URL from which the submodule should be cloned, if present.
	public var url: GitURL

	/// The SHA checked out in the submodule.
	public var sha: String

	public init(name: String, path: String, url: GitURL, sha: String) {
		self.name = name
		self.path = path
		self.url = url
		self.sha = sha
	}
}

extension Submodule: Hashable {
	public static func == (_ lhs: Submodule, _ rhs: Submodule) -> Bool {
		return lhs.name == rhs.name && lhs.path == rhs.path && lhs.url == rhs.url && lhs.sha == rhs.sha
	}

	public var hashValue: Int {
		return name.hashValue
	}
}

extension Submodule: CustomStringConvertible {
	public var description: String {
		return "\(name) @ \(sha)"
	}
}
