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

		if let isAvailable = try? container.decode(Bool.self, forKey: .isAvailable) {
			// Xcode 10.1 ~
			self.isAvailable = isAvailable
		} else if let availability = try container.decodeIfPresent(String.self, forKey: .availability), availability == "(available)" {
			// <= Xcode 10.0
			self.isAvailable = true
		} else if let isAvailable = try container.decodeIfPresent(String.self, forKey: .isAvailable), isAvailable == "YES" {
			// Xcode 10.1 beta
			self.isAvailable = true
		} else {
			self.isAvailable = false
		}
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

	func reducePlatformNames(_ result: inout [String: [Simulator]], _ entry: (key: String, value: [Simulator])) {
		guard let platformVersion = parsePlatformVersion(for: sdk.simulatorJsonKeyUnderDevicesDictQuery, from: entry.key) else { return }
		guard entry.value.contains(where: { $0.isAvailable }) else { return }
		result[platformVersion] = entry.value
	}
	let allTargetSimulators = devices.reduce(into: [:], reducePlatformNames)
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
	return allTargetSimulators[latestOSName]?
		.first { $0.isAvailable }
}

/// Parses a matching platform and version from a given identifier.
///
/// - Warning: Comparing dissimilar — say, hyphenated against "iOS 9.0"-style — is _not_
///            accomodated by chains with this function, (but generally not needed anyway.)
internal func parsePlatformVersion(for platformName: String, from identifier: String) -> String? {
	let asciiDigitCharacterSet = CharacterSet.urlUserAllowed.intersection(CharacterSet.decimalDigits)
	let badEndingCharacterSet = asciiDigitCharacterSet.union(CharacterSet(charactersIn: ".-")).inverted

	let øøø = identifier.suffix(from: identifier.lastIndex(of: " ") ?? identifier.endIndex).dropFirst()
	if
		øøø.unicodeScalars.firstIndex(where: badEndingCharacterSet.contains) == nil,
		identifier.commonPrefix(
			with: platformName.replacingOccurrences(of: " ", with: "-"),
			options: .caseInsensitive
		).isEmpty == false /* btw, `øøø == ""` returns here too · ✓ */
	{
		return [øøø.range(of: ".*", options: .regularExpression)!].reduce(into: identifier) {
			$0.replaceSubrange($1, with: øøø)
		}
	}

	var suffix = identifier.suffix(from: identifier.lastIndex(of: ".") ?? identifier.endIndex).dropFirst()

	// let assumedSpaceReplacementCharacter = "-" // but, as of 2019 no simulator displayNames with spaces in the platform section exist

	let commonality = suffix.commonPrefix(
		with: platformName.replacingOccurrences(of: " ", with: "-").appending("-"),
		options: .caseInsensitive
	)

	guard commonality.isEmpty == false else { return nil }

	guard [platformName, identifier].allSatisfy({ $0.contains("ß") == false }) else { return nil }
	// 〜 that above character matches (when case insensitive) the two character string "SS"
	// 〜 and therefore would nonunify `commonality`’s `endIndex` and where we begin to search for the version

	switch suffix.dropFirst(commonality.count) {
	case "":
		return nil
	case let possibleVersion where possibleVersion.unicodeScalars.firstIndex(where: badEndingCharacterSet.contains) == nil:
		suffix = possibleVersion
	default:
		return nil
	}

	let version = suffix
		.components(separatedBy: asciiDigitCharacterSet.inverted)
		.filter { $0.isEmpty == false }
		.joined(separator: ".")

	// possible for version to contain three+ «.» and four+ numeric components,
	// but later SemanticVersioning parsing will negate those · ✓

	return "\(String(commonality.dropLast(1))) \(version)"
}
