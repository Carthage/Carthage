/// A duplicate dependency, used in CarthageError.duplicateDependencies.
public struct DuplicateDependency {
	/// The duplicate dependency as a project.
	public let project: ProjectIdentifier

	/// The locations where the dependency was found as duplicate.
	public let locations: [String]

	// The generated memberwise initialiser has internal access control and
	// cannot be used in test cases, so we reimplement it as public. We are also
	// sorting locations, which makes sure that we can match them in a
	// test case.
	public init(project: ProjectIdentifier, locations: [String]) {
		self.project = project
		self.locations = locations.sorted(by: <)
	}
}

extension DuplicateDependency: CustomStringConvertible {
	public var description: String {
		return "\(project) \(printableLocations)"
	}

	private var printableLocations: String {
		if locations.isEmpty {
			return ""
		}

		return "(found in "
			+ locations.joined(separator: " and ")
			+ ")"
	}
}

extension DuplicateDependency: Comparable {
	public static func == (_ lhs: DuplicateDependency, _ rhs: DuplicateDependency) -> Bool {
		return lhs.project == rhs.project && lhs.locations == rhs.locations
	}

	public static func < (_ lhs: DuplicateDependency, _ rhs: DuplicateDependency) -> Bool {
		if lhs.description < rhs.description {
			return true
		}

		if lhs.locations.count < rhs.locations.count {
			return true
		}
		else if lhs.locations.count > rhs.locations.count {
			return false
		}

		for (lhsLocation, rhsLocation) in zip(lhs.locations, rhs.locations) {
			if lhsLocation < rhsLocation {
				return true
			}
			else if lhsLocation > rhsLocation {
				return false
			}
		}

		return false
	}
}
