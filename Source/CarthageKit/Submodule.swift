/// A Git submodule.
public struct Submodule: Hashable {
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

extension Submodule: CustomStringConvertible {
	public var description: String {
		return "\(name) @ \(sha)"
	}
}
