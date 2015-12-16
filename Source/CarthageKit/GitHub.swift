//
//  GitHub.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Argo
import Foundation
import Result
import ReactiveCocoa

/// The User-Agent to use for GitHub requests.
private let userAgent: String = {
	let bundle = NSBundle.mainBundle() ?? NSBundle(identifier: CarthageKitBundleIdentifier)
	
	let version = bundle.flatMap {
		($0.objectForInfoDictionaryKey("CFBundleShortVersionString") ??
		 $0.objectForInfoDictionaryKey(kCFBundleVersionKey as String)) as? String
	} ?? "unknown"

	let identifier = bundle?.bundleIdentifier ?? "CarthageKit-unknown"
	return "\(identifier)/\(version)"
}()

/// The type of content to request from the GitHub API.
private let APIContentType = "application/vnd.github.v3+json"

/// The type of content to request from the GitHub API when downloading assets
/// from releases.
private let APIAssetDownloadContentType = "application/octet-stream"

/// Represents an error returned from the GitHub API.
public struct GitHubError: Equatable {
	public let message: String
}

public func ==(lhs: GitHubError, rhs: GitHubError) -> Bool {
	return lhs.message == rhs.message
}

extension GitHubError: Hashable {
	public var hashValue: Int {
		return message.hashValue
	}
}

extension GitHubError: CustomStringConvertible {
	public var description: String {
		return message
	}
}

extension GitHubError: Decodable {
	public static func decode(j: JSON) -> Decoded<GitHubError> {
		return self.init
			<^> j <| "message"
	}
}

/// Describes a GitHub.com or GitHub Enterprise repository.
public struct GitHubRepository: Equatable {

	/// Represents a GitHub server instance.
	public enum Server: Equatable, Hashable, CustomStringConvertible {
		/// The github.com server instance.
		case GitHub

		/// An Enterprise instance with its hostname.
		case Enterprise(scheme: String, hostname: String)

		public var scheme: String {
			switch self {
			case .GitHub:
				return "https"

			case let .Enterprise(scheme, _):
				return scheme
			}
		}

		public var hostname: String {
			switch self {
			case .GitHub:
				return "github.com"

			case let .Enterprise(_, hostname):
				return hostname
			}
		}

		public var APIEndpoint: String {
			switch self {
			case .GitHub:
				return "\(scheme)://api.\(hostname)"

			case .Enterprise:
				return "\(description)/api/v3"
			}
		}

		public var hashValue: Int {
			return scheme.hashValue ^ hostname.hashValue
		}

		public var description: String {
			return "\(scheme)://\(hostname)"
		}
	}

	public let server: Server
	public let owner: String
	public let name: String

	/// The URL that should be used for cloning this repository over HTTPS.
	public var HTTPSURL: GitURL {
		let gitAuth = parseGitHubAccessTokenFromEnvironment()

		var serverAuth:String = ""
		if let auth = gitAuth[server.hostname] {
			serverAuth = "\(auth)@"
		}
		return GitURL("\(server.scheme)://\(serverAuth)\(server.hostname)/\(owner)/\(name).git")
	}

	/// The URL that should be used for cloning this repository over SSH.
	public var SSHURL: GitURL {
		return GitURL("ssh://git@\(server.hostname)/\(owner)/\(name).git")
	}

	/// The URL for filing a new GitHub issue for this repository.
	public var newIssueURL: NSURL {
		return NSURL(string: "\(server)/\(owner)/\(name)/issues/new")!
	}

	public init(server: Server = .GitHub, owner: String, name: String) {
		self.server = server
		self.owner = owner
		self.name = name
	}

	/// Matches an identifier of the form "owner/name".
	private static let NWORegex = try! NSRegularExpression(pattern: "^([\\-\\.\\w]+)/([\\-\\.\\w]+)$", options: [])

	/// Parses repository information out of a string of the form "owner/name"
	/// for the github.com, or the form "http(s)://hostname/owner/name" for
	/// Enterprise instances.
	public static func fromIdentifier(identifier: String) -> Result<GitHubRepository, CarthageError> {
		// GitHub.com
		let range = NSRange(location: 0, length: (identifier as NSString).length)
		if let match = NWORegex.firstMatchInString(identifier, options: [], range: range) {
			let owner = (identifier as NSString).substringWithRange(match.rangeAtIndex(1))
			let name = (identifier as NSString).substringWithRange(match.rangeAtIndex(2))
			return .Success(self.init(owner: owner, name: stripGitSuffix(name)))
		}

		// GitHub Enterprise
		if let
			URL = NSURL(string: identifier),
			host = URL.host,
			// The trailing slash of the host is included in the components.
			var pathComponents = URL.pathComponents?.filter({ $0 != "/" })
			where pathComponents.count >= 2
		{
			// Consider that the instance might be in subdirectories.
			let name = pathComponents.removeLast()
			let owner = pathComponents.removeLast()
			let hostnameWithSubdirectories = (host as NSString).stringByAppendingPathComponent(pathComponents.joinWithSeparator("/"))

			// If the host name starts with “github.com”, that is not an enterprise
			// one.
			if hostnameWithSubdirectories.hasPrefix(Server.GitHub.hostname) {
				return .Success(self.init(owner: owner, name: stripGitSuffix(name)))
			} else {
				return .Success(self.init(server: .Enterprise(scheme: URL.scheme, hostname: hostnameWithSubdirectories), owner: owner, name: stripGitSuffix(name)))
			}
		}

		return .Failure(CarthageError.ParseError(description: "invalid GitHub repository identifier \"\(identifier)\""))
	}
}

public func ==(lhs: GitHubRepository, rhs: GitHubRepository) -> Bool {
	return lhs.server == rhs.server && lhs.owner.caseInsensitiveCompare(rhs.owner) == .OrderedSame && lhs.name.caseInsensitiveCompare(rhs.name) == .OrderedSame
}

public func ==(lhs: GitHubRepository.Server, rhs: GitHubRepository.Server) -> Bool {
	switch (lhs, rhs) {
	case (.GitHub, .GitHub):
		return true

	case let (.Enterprise(la, lb), .Enterprise(ra, rb)):
		return la.caseInsensitiveCompare(ra) == .OrderedSame && lb.caseInsensitiveCompare(rb) == .OrderedSame

	case (_, _):
		return false
	}
}

extension GitHubRepository: Hashable {
	public var hashValue: Int {
		return server.hashValue ^ owner.hashValue ^ name.hashValue
	}
}

extension GitHubRepository: CustomStringConvertible {
	public var description: String {
		let nameWithOwner = "\(owner)/\(name)"
		switch server {
		case .GitHub:
			return nameWithOwner

		case .Enterprise:
			return "\(server)/\(nameWithOwner)"
		}
	}
}

/// Represents a Release on a GitHub repository.
public struct GitHubRelease: Equatable {
	/// The unique ID for this release.
	public let ID: Int

	/// The name of this release.
	public let name: String?

	/// The name of this release, with fallback to its tag when the name is an empty string or nil.
	public var nameWithFallback: String {
		if let name = name where !name.isEmpty {
			return name
		}
		return tag
	}

	/// The name of the tag upon which this release is based.
	public let tag: String

	/// Whether this release is a draft (only visible to the authenticted user).
	public let draft: Bool

	/// Whether this release represents a prerelease version.
	public let prerelease: Bool

	/// Any assets attached to the release.
	public let assets: [Asset]

	/// An asset attached to a GitHub Release.
	public struct Asset: Equatable, Hashable, CustomStringConvertible, Decodable {
		/// The unique ID for this release asset.
		public let ID: Int

		/// The filename of this asset.
		public let name: String

		/// The MIME type of this asset.
		public let contentType: String

		/// The URL at which the asset can be downloaded directly.
		public let URL: NSURL

		public var hashValue: Int {
			return ID.hashValue
		}

		public var description: String {
			return "Asset { name = \(name), contentType = \(contentType), URL = \(URL) }"
		}

		public static func create(ID: Int) -> String -> String -> NSURL -> Asset {
			return { name in { contentType in { URL in
				return self.init(ID: ID, name: name, contentType: contentType, URL: URL)
			} } }
		}

		public static func decode(j: JSON) -> Decoded<Asset> {
			return self.create
				<^> j <| "id"
				<*> j <| "name"
				<*> j <| "content_type"
				<*> j <| "url"
		}
	}
}

public func == (lhs: GitHubRelease, rhs: GitHubRelease) -> Bool {
	return lhs.ID == rhs.ID
}

public func == (lhs: GitHubRelease.Asset, rhs: GitHubRelease.Asset) -> Bool {
	return lhs.ID == rhs.ID
}

extension GitHubRelease: Hashable {
	public var hashValue: Int {
		return ID.hashValue
	}
}

extension GitHubRelease: CustomStringConvertible {
	public var description: String {
		return "Release { ID = \(ID), name = \(name), tag = \(tag) } with assets: \(assets)"
	}
}

extension GitHubRelease: Decodable {
	public static func create(ID: Int) -> String? -> String -> Bool -> Bool -> [Asset] -> GitHubRelease {
		return { name in { tag in { draft in { prerelease in { assets in
			return self.init(ID: ID, name: name, tag: tag, draft: draft, prerelease: prerelease, assets: assets)
		} } } } }
	}

	public static func decode(j: JSON) -> Decoded<GitHubRelease> {
		return self.create
			<^> j <| "id"
			<*> j <|? "name"
			<*> j <| "tag_name"
			<*> j <| "draft"
			<*> j <| "prerelease"
			<*> j <|| "assets"
	}
}

private typealias BasicGitHubCredentials = (String, String)

private func loadCredentialsFromGit(forServer server: GitHubRepository.Server) -> SignalProducer<BasicGitHubCredentials?, CarthageError> {
	let data = "url=\(server)".dataUsingEncoding(NSUTF8StringEncoding)!
	
	return launchGitTask([ "credential", "fill" ], standardInput: SignalProducer(value: data))
		.flatMap(.Concat) { string -> SignalProducer<String, CarthageError> in
			return string.linesProducer.promoteErrors(CarthageError.self)
		}
		.reduce([:]) { (values: [String: String], line: String) -> [String: String] in
			var values = values

			let parts = line.characters
				.split(1, allowEmptySlices: false) { $0 == "=" }
				.map(String.init)

			if parts.count >= 2 {
				let key = parts[0]
				let value = parts[1]
				
				values[key] = value
			}

			return values
		}
		.map { (values: [String: String]) -> BasicGitHubCredentials? in
			if let username = values["username"], password = values["password"] {
				return (username, password)
			}
			
			return nil
		}
		.flatMapError { error in
			return SignalProducer(value: nil)
		}
}

private func parseGitHubAccessTokenFromEnvironment() -> [String: String] {
	let environment = NSProcessInfo.processInfo().environment

	if let accessTokenInput = environment["GITHUB_ACCESS_TOKEN"] {
		// Treat the input as comma-separated series of domains and tokens.
		// (e.g., `GITHUB_ACCESS_TOKEN="github.com=XXXXXXXXXXXXX,enterprise.local/ghe=YYYYYYYYY"`)
		let records = accessTokenInput.characters.split(allowEmptySlices: false) { $0 == "," }

		return records.reduce([:]) { (values: [String: String], record) in
			var values = values

			let parts = record.split(1, allowEmptySlices: false) { $0 == "=" }.map(String.init)
			switch parts.count {
			case 1:
				// If the input is provided as an access token itself, use the
				// token for Github.com.
				values[GitHubRepository.Server.GitHub.hostname] = parts[0]

			case 2:
				let (key, value) = (parts[0], parts[1])
				values[key] = value

			default:
				break
			}

			return values
		}
	}
	
	return [:]
}

internal func loadGitHubAuthorization(forServer server: GitHubRepository.Server) -> SignalProducer<String?, CarthageError> {
	if let accessTokenForServer = parseGitHubAccessTokenFromEnvironment()[server.hostname] {
		return SignalProducer(value: "token \(accessTokenForServer)")
	} else {
		return loadCredentialsFromGit(forServer: server).map { maybeCredentials in
			maybeCredentials.map { (username, password) in
				let data = "\(username):\(password)".dataUsingEncoding(NSUTF8StringEncoding)!
				let encodedString = data.base64EncodedStringWithOptions([])
				return "Basic \(encodedString)"
			}
		}
	}
}

/// Creates a request to fetch the given GitHub URL, optionally authenticating
/// with the given credentials and content type.
internal func createGitHubRequest(URL: NSURL, _ authorizationHeaderValue: String?, contentType: String = APIContentType) -> NSURLRequest {
	let request = NSMutableURLRequest(URL: URL)
	request.setValue(contentType, forHTTPHeaderField: "Accept")
	request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

	if let authorizationHeaderValue = authorizationHeaderValue {
		request.setValue(authorizationHeaderValue, forHTTPHeaderField: "Authorization")
	}

	return request
}

/// Parses the value of a `Link` header field into a list of URLs and their
/// associated parameter lists.
private func parseLinkHeader(linkValue: String) -> [(NSURL, [String])] {
	let components = linkValue.characters.split(allowEmptySlices: false) { $0 == "," }

	return components.reduce([]) { links, component in
		var links = links

		var pieces = component.split(allowEmptySlices: false) { $0 == ";" }
		if let URLPiece = pieces.first {
			pieces.removeAtIndex(0)

			let scanner = NSScanner(string: String(URLPiece))

			var URLString: NSString?
			if scanner.scanString("<", intoString: nil) && scanner.scanUpToString(">", intoString: &URLString) {
				if let URL = NSURL(string: URLString! as String) {
					let value: (NSURL, [String]) = (URL, pieces.map(String.init))
					links.append(value)
				}
			}
		}

		return links
	}
}

/// Fetches the given GitHub URL, automatically paginating to the end.
///
/// Returns a signal that will send one `NSData` for each page fetched.
private func fetchAllPages(URL: NSURL, _ authorizationHeaderValue: String?) -> SignalProducer<NSData, CarthageError> {
	let request = createGitHubRequest(URL, authorizationHeaderValue)

	return NSURLSession.sharedSession().rac_dataWithRequest(request)
		.mapError(CarthageError.NetworkError)
		.flatMap(.Concat) { data, response -> SignalProducer<NSData, CarthageError> in
			let thisData: SignalProducer<NSData, CarthageError> = SignalProducer(value: data)

			if let HTTPResponse = response as? NSHTTPURLResponse {
				let statusCode = HTTPResponse.statusCode
				if statusCode > 400 && statusCode < 600 && statusCode != 404 {
					return thisData
						.attemptMap { data -> Result<AnyObject, CarthageError> in
							if let object = try? NSJSONSerialization.JSONObjectWithData(data, options: []) {
								return .Success(object)
							} else {
								return .Failure(.ParseError(description: "Invalid JSON in API error response \(data)"))
							}
						}
						.map { (dictionary: AnyObject) -> String in
							if let error: GitHubError = decode(dictionary) {
								return error.message
							} else {
								return (NSString(data: data, encoding: NSUTF8StringEncoding) ?? NSHTTPURLResponse.localizedStringForStatusCode(statusCode)) as String
							}
						}
						.flatMapError { (error: CarthageError) in
							return SignalProducer(value: error.description)
						}
						.attemptMap { message -> Result<NSData, CarthageError> in
							return Result.Failure(CarthageError.GitHubAPIRequestFailed(message))
						}
				}
				
				if let linkHeader = HTTPResponse.allHeaderFields["Link"] as? String {
					let links = parseLinkHeader(linkHeader)
					for (URL, parameters) in links {
						if parameters.contains("rel=\"next\"") {
							// Automatically fetch the next page too.
							return thisData.concat(fetchAllPages(URL, authorizationHeaderValue))
						}
					}
				}
			}

			return thisData
		}
}

/// Fetches the release corresponding to the given tag on the given repository,
/// sending it along the returned signal. If no release matches, the signal will
/// complete without sending any values.
internal func releaseForTag(tag: String, _ repository: GitHubRepository, _ authorizationHeaderValue: String?) -> SignalProducer<GitHubRelease, CarthageError> {
	return fetchAllPages(NSURL(string: "\(repository.server.APIEndpoint)/repos/\(repository.owner)/\(repository.name)/releases/tags/\(tag)")!, authorizationHeaderValue)
		.attemptMap { data -> Result<AnyObject, CarthageError> in
			if let object = try? NSJSONSerialization.JSONObjectWithData(data, options: []) {
				return .Success(object)
			} else {
				return .Failure(.ParseError(description: "Invalid JSON in releases for tag \(tag)"))
			}
		}
		.flatMap(.Concat) { releaseDictionary -> SignalProducer<GitHubRelease, CarthageError> in
			if let release: GitHubRelease = decode(releaseDictionary) {
				return SignalProducer(value: release)
			} else {
				// The response didn't error, but didn't return a release. That means it's either a
				// tag (but not a release) or a SHA.
				return .empty
			}
		}
}

/// Downloads the indicated release asset to a temporary file, returning the
/// URL to the file on disk.
///
/// The downloaded file will be deleted after the URL has been sent upon the
/// signal.
internal func downloadAsset(asset: GitHubRelease.Asset, _ authorizationHeaderValue: String?) -> SignalProducer<NSURL, CarthageError> {
	let request = createGitHubRequest(asset.URL, authorizationHeaderValue, contentType: APIAssetDownloadContentType)

	return NSURLSession.sharedSession().carthage_downloadWithRequest(request)
		.mapError(CarthageError.NetworkError)
		.map { URL, _ in URL }
}
