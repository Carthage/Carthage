import Foundation
import Result

/// Represents a binary dependency 
public struct BinaryProject: Equatable {
	private static let jsonDecoder = JSONDecoder()

	public var versions: [PinnedVersion: URL]

	public static func from(jsonData: Data) -> Result<BinaryProject, BinaryJSONError> {
		return Result<[String: String], AnyError>(attempt: { try jsonDecoder.decode([String: String].self, from: jsonData) })
			.mapError { .invalidJSON($0.error) }
			.flatMap { json -> Result<BinaryProject, BinaryJSONError> in
				var versions = [PinnedVersion: URL]()

				for (key, value) in json {
					let pinnedVersion: PinnedVersion
					switch SemanticVersion.from(Scanner(string: key)) {
					case .success:
						pinnedVersion = PinnedVersion(key)
					case let .failure(error):
						return .failure(BinaryJSONError.invalidVersion(error))
					}

					guard let binaryURL = URL(string: value) else {
						return .failure(BinaryJSONError.invalidURL(value))
					}
					guard binaryURL.scheme == "file" || binaryURL.scheme == "https" else {
						return .failure(BinaryJSONError.nonHTTPSURL(binaryURL))
					}

					versions[pinnedVersion] = binaryURL
				}

				return .success(BinaryProject(versions: versions))
			}
	}
}
