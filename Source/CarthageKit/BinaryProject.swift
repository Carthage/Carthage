import Foundation
import Result
import Utility

import struct Foundation.URL

/// Represents a binary dependency 
public struct BinaryProject: Equatable {
	private static let jsonDecoder = JSONDecoder()

	public var versions: [PinnedVersion: URL]

    public static func from(jsonData: Data, allowHTTP: Bool = false) -> Result<BinaryProject, BinaryJSONError> {
		return Result<[String: String], AnyError>(attempt: { try jsonDecoder.decode([String: String].self, from: jsonData) })
			.mapError { .invalidJSON($0.error) }
			.flatMap { json -> Result<BinaryProject, BinaryJSONError> in
				var versions = [PinnedVersion: URL]()

				for (key, value) in json {
					let pinnedVersion: PinnedVersion
					switch Version.from(Scanner(string: key)) {
					case .success:
						pinnedVersion = PinnedVersion(key)
					case let .failure(error):
						return .failure(BinaryJSONError.invalidVersion(error))
					}

					guard let binaryURL = URL(string: value) else {
						return .failure(BinaryJSONError.invalidURL(value))
					}
                    guard binaryURL.validateScheme(allowHTTP: allowHTTP) else {
                        return .failure(BinaryJSONError.invalidURLScheme(binaryURL))
                    }

					versions[pinnedVersion] = binaryURL
				}

				return .success(BinaryProject(versions: versions))
			}
	}
}
