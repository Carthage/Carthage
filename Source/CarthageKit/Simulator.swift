import Foundation

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
