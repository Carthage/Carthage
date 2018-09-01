import Foundation
import XCDBLD

internal struct Simulator: Decodable {
	enum Availability: String, Decodable {
		case available
		case unavailable

		init(from decoder: Decoder) throws {
			let container = try decoder.singleValueContainer()
			let rawString = try container.decode(String.self)
			if rawString == "(available)" {
				self = .available
			} else {
				self = .unavailable
			}
		}
	}

	var isAvailable: Bool {
		return availability == .available
	}

	var availability: Availability
	var name: String
	var udid: UUID
}

/// Select available simulator from output value of `simclt devices list`
/// If there are multiple OSs for the SDK, the latest one would be selected.
internal func selectAvailableSimulator(of sdk: SDK, from data: Data) -> Simulator? {
	let decoder = JSONDecoder()
	// simctl returns following JSON:
	// {"devices": {"iOS 12.0": [<simulators...>]}]
	guard let jsonObject = try? decoder.decode([String: [String: [Simulator]]].self, from: data),
		let devices = jsonObject["devices"] else {
		return nil
	}
	let platformName = sdk.platform.rawValue
	let allTargetSimulators = devices
		.filter { $0.key.hasPrefix(platformName) }
	func sortedByVersion(_ osNames: [String]) -> [String] {
		return osNames.sorted { lhs, rhs in
			guard let lhsVersion = SemanticVersion.from(PinnedVersion(lhs)).value,
				let rhsVersion = SemanticVersion.from(PinnedVersion(rhs)).value else {
					return lhs < rhs
			}
			return lhsVersion < rhsVersion
		}
	}
	guard let latestOSName = sortedByVersion(Array(allTargetSimulators.keys)).last else {
		return nil
	}
	return devices[latestOSName]?
		.first { $0.isAvailable }
}
