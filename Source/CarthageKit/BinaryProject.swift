import Foundation
import Result

/// Represents a binary dependency 
public struct BinaryProject: Equatable {
	private static let jsonDecoder = JSONDecoder()
	private static let urlExpectedQueryParameter = "carthage-alt"
	private static let urlOptionalQueryParameter = "alt"

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

					var binaryURLs: [URL] = []
					var remainingQueryItems: [URLQueryItem]?

					for item in components.queryItems ?? [] {
						if item.name == urlExpectedQueryParameter, let value = item.value {
							switch getValidBinaryUrl(value: value) {
							case .success(let url):
								binaryURLs.append(url)
							case .failure(let error):
								return .failure(error)
							}
						} else if item.name == urlOptionalQueryParameter, let value = item.value, case let .success(url) = getValidBinaryUrl(value: value) {
							binaryURLs.append(url)
						} else if remainingQueryItems == nil {
							remainingQueryItems = [item]
						} else {
							remainingQueryItems!.append(item)
						}
					}

					components.queryItems = remainingQueryItems

					guard let firstURL = components.string else {
						return .failure(BinaryJSONError.invalidURL(value))
					}

					switch getValidBinaryUrl(value: firstURL) {
					case .success(let url):
						binaryURLs.insert(url, at: 0)
					case .failure(let error):
						return .failure(error)
					}

					versions[pinnedVersion] = binaryURLs
				}

				return .success(BinaryProject(versions: versions))
			}
	}

	public static func getValidBinaryUrl(value: String) -> Result<URL, BinaryJSONError> {
		guard let url = URL(string: value) else {
			return .failure(BinaryJSONError.invalidURL(value))
		}

		guard url.scheme == "file" || url.scheme == "https" else {
			return .failure(BinaryJSONError.nonHTTPSURL(url))
		}

		return .success(url)
	}
}
