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
import Runes

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

extension GitHubError: Printable {
	public var description: String {
		return message
	}
}

extension GitHubError: Decodable {
	public static func create(message: String) -> GitHubError {
		return self(message: message)
	}
	
	public static func decode(j: JSON) -> Decoded<GitHubError> {
		return self.create
			<^> j <| "message"
	}
}

/// Describes a GitHub.com repository.
public struct GitHubRepository: Equatable {
	public let owner: String
	public let name: String

	/// The URL that should be used for cloning this repository over HTTPS.
	public var HTTPSURL: GitURL {
		return GitURL("https://github.com/\(owner)/\(name).git")
	}

	/// The URL that should be used for cloning this repository over SSH.
	public var SSHURL: GitURL {
		return GitURL("ssh://git@github.com/\(owner)/\(name).git")
	}

	/// The URL for filing a new GitHub issue for this repository.
	public var newIssueURL: NSURL {
		return NSURL(string: "https://github.com/\(owner)/\(name)/issues/new")!
	}

	public init(owner: String, name: String) {
		self.owner = owner
		self.name = name
	}

	/// Parses repository information out of a string of the form "owner/name".
	public static func fromNWO(NWO: String) -> Result<GitHubRepository, CarthageError> {
		let components = split(NWO, maxSplit: 1, allowEmptySlices: false) { $0 == "/" }
		if components.count < 2 {
			return .failure(CarthageError.ParseError(description: "invalid GitHub repository name \"\(NWO)\""))
		}

		return .success(self(owner: components[0], name: components[1]))
	}
}

public func ==(lhs: GitHubRepository, rhs: GitHubRepository) -> Bool {
	return lhs.owner.caseInsensitiveCompare(rhs.owner) == .OrderedSame && lhs.name.caseInsensitiveCompare(rhs.name) == .OrderedSame
}

extension GitHubRepository: Hashable {
	public var hashValue: Int {
		return owner.hashValue ^ name.hashValue
	}
}

extension GitHubRepository: Printable {
	public var description: String {
		return "\(owner)/\(name)"
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
	public struct Asset: Equatable, Hashable, Printable, Decodable {
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

		public static func create(ID: Int)(name: String)(contentType: String)(URL: NSURL) -> Asset {
			return self(ID: ID, name: name, contentType: contentType, URL: URL)
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

extension GitHubRelease: Printable {
	public var description: String {
		return "Release { ID = \(ID), name = \(name), tag = \(tag) } with assets: \(assets)"
	}
}

extension GitHubRelease: Decodable {
	public static func create(ID: Int)(name: String?)(tag: String)(draft: Bool)(prerelease: Bool)(assets: [Asset]) -> GitHubRelease {
		return self(ID: ID, name: name, tag: tag, draft: draft, prerelease: prerelease, assets: assets)
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

private func loadCredentialsFromGit() -> SignalProducer<BasicGitHubCredentials?, CarthageError> {
	let data = "url=https://github.com".dataUsingEncoding(NSUTF8StringEncoding)!
	
	var environment = NSProcessInfo.processInfo().environment as! [String: String]
	environment["GIT_TERMINAL_PROMPT"] = "0"
	
	return launchGitTask([ "credential", "fill" ], standardInput: SignalProducer(value: data), environment: environment)
		|> flatMap(.Concat) { string -> SignalProducer<String, CarthageError> in
			return string.linesProducer |> promoteErrors(CarthageError.self)
		}
		|> reduce([:]) { (var values: [String: String], line: String) -> [String: String] in
			let parts = split(line, maxSplit: 1, allowEmptySlices: false) { $0 == "=" }
			if parts.count >= 2 {
				let key = parts[0]
				let value = parts[1]
				
				values[key] = value
			}
			
			return values
		}
		|> map { (values: [String: String]) -> BasicGitHubCredentials? in
			if let username = values["username"] {
				if let password = values["password"] {
					return (username, password)
				}
			}
			
			return nil
		}
		|> catch { error in
			return SignalProducer(value: nil)
	}
}


internal func loadGitHubAuthorization() -> SignalProducer<String?, CarthageError> {
	let environment = NSProcessInfo.processInfo().environment
	if let accessToken = environment["GITHUB_ACCESS_TOKEN"] as? String {
		return SignalProducer(value: "token \(accessToken)")
	} else {
		return loadCredentialsFromGit() |> map { maybeCredentials in
			maybeCredentials.map { (username, password) in
				let data = "\(username):\(password)".dataUsingEncoding(NSUTF8StringEncoding)!
				let encodedString = data.base64EncodedStringWithOptions(nil)
				return "Basic \(encodedString)"
			}
		}
	}
}

/// Creates a request to fetch the given GitHub URL, optionally authenticating
/// with the given credentials and content type.
internal func createGitHubRequest(URL: NSURL, authorizationHeaderValue: String?, contentType: String = APIContentType) -> NSURLRequest {
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
	let components = split(linkValue, allowEmptySlices: false) { $0 == "," }

	return reduce(components, []) { (var links, component) in
		var pieces = split(component, allowEmptySlices: false) { $0 == ";" }
		if let URLPiece = pieces.first {
			pieces.removeAtIndex(0)

			let scanner = NSScanner(string: URLPiece)

			var URLString: NSString?
			if scanner.scanString("<", intoString: nil) && scanner.scanUpToString(">", intoString: &URLString) {
				if let URL = NSURL(string: URLString! as String) {
					let value: (NSURL, [String]) = (URL, pieces)
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
private func fetchAllPages(URL: NSURL, authorizationHeaderValue: String?) -> SignalProducer<NSData, CarthageError> {
	let request = createGitHubRequest(URL, authorizationHeaderValue)

	return NSURLSession.sharedSession().rac_dataWithRequest(request)
		|> mapError { .NetworkError($0) }
		|> flatMap(.Concat) { data, response in
			let thisData: SignalProducer<NSData, CarthageError> = SignalProducer(value: data)

			if let HTTPResponse = response as? NSHTTPURLResponse {
				let statusCode = HTTPResponse.statusCode
				if statusCode > 400 && statusCode < 600 && statusCode != 404 {
					return thisData
						|> tryMap { data -> Result<AnyObject, CarthageError> in
							if let object: AnyObject = NSJSONSerialization.JSONObjectWithData(data, options: nil, error: nil) {
								return .success(object)
							} else {
								return .failure(.ParseError(description: "Invalid JSON in API error response \(data)"))
							}
						}
						|> map { (dictionary: AnyObject) -> String in
							if let error: GitHubError = decode(dictionary) {
								return error.message
							} else {
								return (NSString(data: data, encoding: NSUTF8StringEncoding) ?? NSHTTPURLResponse.localizedStringForStatusCode(statusCode)) as String
							}
						}
						|> catch { (error: CarthageError) in
							return SignalProducer(value: error.description)
						}
						|> tryMap { message -> Result<NSData, CarthageError> in
							return Result.failure(CarthageError.GitHubAPIRequestFailed(message))
						}
				}
				
				if let linkHeader = HTTPResponse.allHeaderFields["Link"] as? String {
					let links = parseLinkHeader(linkHeader)
					for (URL, parameters) in links {
						if contains(parameters, "rel=\"next\"") {
							// Automatically fetch the next page too.
							return thisData |> concat(fetchAllPages(URL, authorizationHeaderValue))
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
internal func releaseForTag(tag: String, repository: GitHubRepository, authorizationHeaderValue: String?) -> SignalProducer<GitHubRelease, CarthageError> {
	return fetchAllPages(NSURL(string: "https://api.github.com/repos/\(repository.owner)/\(repository.name)/releases/tags/\(tag)")!, authorizationHeaderValue)
		|> tryMap { data -> Result<AnyObject, CarthageError> in
			if let object: AnyObject = NSJSONSerialization.JSONObjectWithData(data, options: nil, error: nil) {
				return .success(object)
			} else {
				return .failure(.ParseError(description: "Invalid JSON in releases for tag \(tag)"))
			}
		}
		|> flatMap(.Concat) { releaseDictionary -> SignalProducer<GitHubRelease, CarthageError> in
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
internal func downloadAsset(asset: GitHubRelease.Asset, authorizationHeaderValue: String?) -> SignalProducer<NSURL, CarthageError> {
	let request = createGitHubRequest(asset.URL, authorizationHeaderValue, contentType: APIAssetDownloadContentType)

	return NSURLSession.sharedSession().carthage_downloadWithRequest(request)
		|> mapError { .NetworkError($0) }
		|> map { URL, _ in URL }
}
