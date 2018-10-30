import Foundation
import XCDBLD

internal struct Simulator: Decodable {
	enum CodingKeys: String, CodingKey {
		case name
		case udid
		case isAvailable
		case availability
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		name = try container.decode(String.self, forKey: .name)
		udid = try container.decode(UUID.self, forKey: .udid)
		// Up until Xcode 10.0, values returned from `xcrun simctl list devices --json`
		// include an `availability` string field.
		// Its possible values are either `(available)` or `(unavailable)`.
		// Starting from Xcode 10.1, the `availability` field has been marked as obsolete.
		// and replaced with the `isAvailable` boolean field.
		guard let isAvailable = try container.decodeIfPresent(Bool.self, forKey: .isAvailable) else {
			// Fallback to Xcode <= 10.0 behavior using `availability`
			let availability = try container.decodeIfPresent(String.self, forKey: .availability)
			self.isAvailable = availability == "(available)"
			return
		}
		self.isAvailable = isAvailable
	}

	var isAvailable: Bool
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
