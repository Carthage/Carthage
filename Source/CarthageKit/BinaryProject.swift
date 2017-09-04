import Foundation
import Result

public struct BinaryProject {
	public var versions: [PinnedVersion: URL]

	public static func from(jsonData: Data) -> Result<BinaryProject, BinaryJSONError> {
		return Result<Any, NSError>(attempt: { try JSONSerialization.jsonObject(with: jsonData, options: []) })
			.mapError(BinaryJSONError.invalidJSON)
			.flatMap { json in
				let error = NSError(
					domain: Constants.bundleIdentifier,
					code: 1,
					userInfo: [NSLocalizedDescriptionKey: "Binary definition was not expected type [String: String]"]
				)
				return Result(json as? [String: String], failWith: BinaryJSONError.invalidJSON(error))
			}
			.flatMap { (json: [String: String]) -> Result<BinaryProject, BinaryJSONError> in
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

extension BinaryProject: Equatable {
	public static func == (lhs: BinaryProject, rhs: BinaryProject) -> Bool {
		return lhs.versions == rhs.versions
	}
}
