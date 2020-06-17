import Foundation
import Result
import ReactiveTask
import ReactiveSwift

/// - Note: Previously, `SDK` as an enum had a hardcoded set of values,
///         and was associated with a hardcoded set of `Platform`s —
///         where `Platform`s were pretty much SDK value minus simulator.
///
///         Now, `SDK`s no longer have the constraint of being hardcoded-in
///         and in areas where `Platform` was interpolated, we use
///         `platformSimulatorlessFromHeuristic` which (in practice) usually
///         draws upon data from `xcodebuild -showsdks -json`.
public struct SDK: Hashable {
	private let name: String
	private let simulatorHeuristic: String
	// it’s a fairly solid heuristic

	public init(name: String, simulatorHeuristic: String) {
		(self.name, self.simulatorHeuristic) = (name, simulatorHeuristic)
	}

	public var rawValue: String { return name.lowercased() }

	public var isSimulator: Bool {
		return ["simulator"].contains(where: {
			simulatorHeuristic.prefix(12).caseInsensitiveCompare($0 + " - ") == .orderedSame
				|| (
					name.suffix(9).caseInsensitiveCompare($0) == .orderedSame
						&& name.suffix(18).caseInsensitiveCompare($0 + $0) != .orderedSame
				)
		})
	}

	public var isDevice: Bool {
		return !isSimulator
	}

	public func hash(into: inout Hasher) {
		return into.combine(self.rawValue)
	}

	public static func == (lhs: SDK, rhs: SDK) -> Bool {
		return lhs.rawValue == rhs.rawValue
	}

	/// Take `simulatorHeuristic` and (best as possible) derive what used to be `XCDBLD.Platform` from it.
	/// With data from `xcodebuild -showsdks -json`, should do solid job.
	public var platformSimulatorlessFromHeuristic: String {
		guard self.rawValue != "macosx" else { return "Mac" }

		guard simulatorHeuristic.isEmpty == false else {
			let result = SDK.knownIn2019YearDictionary[self.rawValue, default: ("", [""], "")].1
			guard result.first != .some("") else {
				return ["simulator"].reduce(into: self.name) {
					let suffix = $0.suffix($1.utf8.count)
					guard String(suffix).caseInsensitiveCompare($1) == .orderedSame else { return }
					$0.removeSubrange(suffix.startIndex...)
				}
			}

			// essentially, the above asserts that `result.first?.firstIndex(of: " ") != nil`
			// because of our hardcoded `knownIn2019YearDictionary`
			return String(
				result.first!.split(separator: " ", omittingEmptySubsequences: true).first!
			)
		}

		return ["simulator - "].reduce(into: simulatorHeuristic) {
			let prefix = $0.commonPrefix(with: $1, options: .caseInsensitive)
			guard prefix.isEmpty == false else { return }
			$0.removeSubrange(..<prefix.endIndex)
		}
	}

	/// - Returns: The name with correct titlecasing, an array of aliases, and a
	///            hardcoded `simulatorHeuristic` · all keyed by lowercased `name`.
	/// - Note: The aliases are intended to be matched case-insensitevly.
	private static let knownIn2019YearDictionary: [String: (String, [String], String)] =
		KeyValuePairs.reduce([
			"MacOSX": (["macOS", "Mac", "OSX"], "macOS"),
			"iPhoneOS": (["iOS Device", "iOS"], "iOS"),
			"iPhoneSimulator": (["iOS Simulator"], "Simulator - iOS"),
			"WatchOS": (["watchOS"], "watchOS"),
			"WatchSimulator": (["watchOS Simulator", "watchsimulator"], "Simulator - watchOS"),
			"AppleTVOS": (["tvOS"], "tvOS"),
			"AppleTVSimulator": (["tvOS Simulator", "appletvsimulator", "tvsimulator"], "Simulator - tvOS"),
		])(into: [:]) {
			$0[$1.0.lowercased()] = ($1.0, $1.1.0, $1.1.1)
		}

	public static let knownIn2019YearSDKs: Set<SDK> =
		Set(
			knownIn2019YearDictionary
				.mapValues { $0.2 }
				.map(SDK.init)
		)

	/// - Warning:
	public init?(rawValue: String) {
		if rawValue.caseInsensitiveCompare("tvos") == .orderedSame {
			self.name = "AppleTVOS"
			self.simulatorHeuristic = ""
			return
		}

		guard let index = SDK.knownIn2019YearDictionary.index(forKey: rawValue.lowercased()) else { return nil }

		(self.name, _, self.simulatorHeuristic) = SDK.knownIn2019YearDictionary[index].value
	}

	public static func associatedSetOfKnownIn2019YearSDKs(_ argumentSubstring: String) -> Set<SDK> {
		let knownIn2019YearDictionary = SDK.knownIn2019YearDictionary
		let potentialSDK = argumentSubstring.lowercased()

		let potentialIndex = knownIn2019YearDictionary.index(forKey: potentialSDK)
			?? knownIn2019YearDictionary.firstIndex(
				where: { _, value in
					value.1.contains { $0.caseInsensitiveCompare(potentialSDK) == .orderedSame }
				}
			)

		guard let index = potentialIndex else { return Set() }

		return [
			Optional(knownIn2019YearDictionary[index].value),
			knownIn2019YearDictionary[knownIn2019YearDictionary[index].key.dropLast(2).appending("simulator")],
			knownIn2019YearDictionary[knownIn2019YearDictionary[index].key.dropLast(9).appending("os")]
		]
			.reduce(into: [] as Set<SDK>) {
				guard let value = $1 else { return }
				$0.formUnion([SDK(name: value.0, simulatorHeuristic: value.2)])
			}
	}
}

// swiftlint:disable force_cast

extension SDK {
	/// - Note: Will, if available, use the version of `xcodebuild` from `DEVELOPER_DIR`.
	/// - Note: Will omit SDKs — like DriverKit — where `canonicalName` and `platform`
	///         do not share a common prefix.
	public static let setFromJSONShowSDKs: SignalProducer<Set<SDK>?, NoError> =
		Task("/usr/bin/xcrun", arguments: ["xcodebuild", "-showsdks", "-json"])
			.launch()
			.materializeResults() // to map below and ignore errors
			.filterMap { try? JSONSerialization.jsonObject(with: $0.value?.value ?? Data(bytes: []), options: JSONSerialization.ReadingOptions()) as? NSArray ?? NSArray() }
			.map {
                $0.compactMap { (nsobject: Any) -> SDK? in
					let platform = NSString.lowercased(
						(nsobject as! NSObject).value(forKey: "platform") as? NSString ?? ""
					)(with: Locale?.none)

					guard platform.isEmpty == false else { return nil }

					guard NSString.lowercased(
						(nsobject as! NSObject).value(forKey: "canonicalName") as? NSString ?? "\0"
					)(with: Locale?.none).hasPrefix(platform) else { return nil }

					let simulatorHeuristic = CollectionOfOne(
						(nsobject as! NSObject).value(forKey: "displayName") as? NSString
					).reduce(into: "") {
						$0 = $1?.appending("") ?? $0
						let potentialVersion = $0.reversed().drop(while: "1234567890.".contains)
						guard potentialVersion.firstIndex(of: ".") == potentialVersion.lastIndex(of: ".") else {
							return
						}

						$0 = String(potentialVersion.base.suffix(from: potentialVersion.startIndex).dropFirst().reversed())
					}

					let parseTitleCasePlatform: (String) -> String? = {
						let index = $0.lastIndex(of: "/") ?? $0.startIndex
						switch $0[index...].dropFirst().prefix(platform.count) {
						case let string where string.caseInsensitiveCompare(platform) == .orderedSame:
							return String(string)
						default:
							return nil
						}
					}

					let titleCasedPlatform = repeatElement(
						(nsobject as! NSObject).value(forKey: "platformPath") as? NSString ?? "", count: 1
					).reduce(into: String?.none) { $0 = parseTitleCasePlatform($1.appending("")) }

                    return SDK(name: titleCasedPlatform ?? platform, simulatorHeuristic: simulatorHeuristic)
				}
			}
			.reduce(into: Set<SDK>?.none) {
				guard $0 == nil else { return }
				$0 = Set($1)
			}
}

extension SDK: CustomStringConvertible {
	public var description: String {
		return SDK.knownIn2019YearDictionary[self.rawValue]?.1.first!
			?? self.platformSimulatorlessFromHeuristic.appending(self.isSimulator ? " Simulator" : "")
	}
}
