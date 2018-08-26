import Foundation

internal struct Simulator: Decodable {
	enum Availavility: String, Decodable {
		case available
		case unavailable

		init(from decoder: Decoder) throws {
			var container = try decoder.singleValueContainer()
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

	var availability: Availavility
	var name: String
	var udid: UUID
}
