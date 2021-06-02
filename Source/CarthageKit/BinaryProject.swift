import Foundation
import Result

/// Represents a binary dependency 
public struct BinaryProject: Equatable {
	private static let jsonDecoder = JSONDecoder()

	public var versions: [PinnedVersion: [URL]]

	public static func from(jsonData: Data) -> Result<BinaryProject, BinaryJSONError> {
		return Result<[String: String], AnyError>(attempt: { try jsonDecoder.decode([String: String].self, from: jsonData) })
			.mapError { .invalidJSON($0.error) }
			.flatMap { json -> Result<BinaryProject, BinaryJSONError> in
				var versions = [PinnedVersion: [URL]]()

				for (key, value) in json {
					let pinnedVersion: PinnedVersion
					switch SemanticVersion.from(Scanner(string: key)) {
					case .success:
						pinnedVersion = PinnedVersion(key)
					case let .failure(error):
						return .failure(BinaryJSONError.invalidVersion(error))
					}
					
					guard var components = URLComponents(string: value) else {
						return .failure(BinaryJSONError.invalidURL(value))
					}

					struct ExtractedURLs {
						var remainingQueryItems: [URLQueryItem]? = nil
						var urlStrings: [String] = []
					}
					let extractedURLs = components.queryItems?.reduce(into: ExtractedURLs()) { state, item in
						if item.name == "carthage-alt", let value = item.value {
							state.urlStrings.append(value)
						} else if state.remainingQueryItems == nil {
							state.remainingQueryItems = [item]
						} else {
							state.remainingQueryItems!.append(item)
						}
					}
					components.queryItems = extractedURLs?.remainingQueryItems

					guard let firstURL = components.url else {
						return .failure(BinaryJSONError.invalidURL(value))
					}
					guard firstURL.scheme == "file" || firstURL.scheme == "https" else {
						return .failure(BinaryJSONError.nonHTTPSURL(firstURL))
					}
					var binaryURLs: [URL] = [firstURL]

					if let extractedURLs = extractedURLs {
						for string in extractedURLs.urlStrings {
							guard let binaryURL = URL(string: string) else {
								return .failure(BinaryJSONError.invalidURL(string))
							}
							guard binaryURL.scheme == "file" || binaryURL.scheme == "https" else {
								return .failure(BinaryJSONError.nonHTTPSURL(binaryURL))
							}
							binaryURLs.append(binaryURL)
						}
					}
					
					versions[pinnedVersion] = binaryURLs
				}

				return .success(BinaryProject(versions: versions))
			}
	}
}
