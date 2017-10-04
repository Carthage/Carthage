/// Represents a scheme to be built
public struct Scheme {
	public let name: String

	public init(_ name: String) {
		self.name = name
	}
}

extension Scheme: Equatable {
	public static func == (lhs: Scheme, rhs: Scheme) -> Bool {
		return lhs.name == rhs.name
	}
}

extension Scheme: CustomStringConvertible {
	public var description: String {
		return name
	}
}
