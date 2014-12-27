//
//  GitHub.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Argo
import Foundation
import LlamaKit
import ReactiveCocoa

/// The User-Agent to use for GitHub requests.
private let userAgent: String = {
	let bundle = NSBundle.mainBundle() ?? NSBundle(identifier: CarthageKitBundleIdentifier)
	let version: AnyObject = bundle?.objectForInfoDictionaryKey("CFBundleShortVersionString") ?? bundle?.objectForInfoDictionaryKey(kCFBundleVersionKey) ?? "unknown"
	let identifier = bundle?.bundleIdentifier ?? "CarthageKit-unknown"

	return "\(identifier)/\(version)"
}()

/// The type of content to request from the GitHub API.
private let APIContentType = "application/vnd.github.v3+json"

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

	public init(owner: String, name: String) {
		self.owner = owner
		self.name = name
	}

	/// Parses repository information out of a string of the form "owner/name".
	public static func fromNWO(NWO: String) -> Result<GitHubRepository> {
		let components = split(NWO, { $0 == "/" }, maxSplit: 1, allowEmptySlices: false)
		if components.count < 2 {
			return failure(CarthageError.ParseError(description: "invalid GitHub repository name \"\(NWO)\"").error)
		}

		return success(self(owner: components[0], name: components[1]))
	}
}

public func ==(lhs: GitHubRepository, rhs: GitHubRepository) -> Bool {
	return lhs.owner == rhs.owner && lhs.name == rhs.name
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
	public let ID: String

	/// The name of the tag upon which this release is based.
	public let tag: String

	/// Whether this release is a draft (only visible to the authenticted user).
	public let draft: Bool

	/// Whether this release represents a prerelease version.
	public let prerelease: Bool

	/// Any assets attached to the release.
	public let assets: [Asset]

	/// An asset attached to a GitHub Release.
	public struct Asset: Equatable, Hashable, Printable, JSONDecodable {
		/// The unique ID for this release asset.
		public let ID: String

		/// The filename of this asset.
		public let name: String

		/// The MIME type of this asset.
		public let contentType: String

		/// The URL at which the asset can be downloaded directly.
		public let downloadURL: NSURL

		public var hashValue: Int {
			return ID.hashValue
		}

		public var description: String {
			return "Asset { name = \(name), contentType = \(contentType), downloadURL = \(downloadURL) }"
		}

		public static func create(ID: String)(name: String)(contentType: String)(downloadURL: NSURL) -> Asset {
			return self(ID: ID, name: name, contentType: contentType, downloadURL: downloadURL)
		}

		public static var decoder: JSONValue -> Asset? {
			return self.create
				<^> <|"id"
				<*> <|"name"
				<*> <|"content_type"
				<*> decodeURLFromJSON("browser_download_url")
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
		return "Release { ID = \(ID), tag = \(tag) } with assets: \(assets)"
	}
}

extension GitHubRelease: JSONDecodable {
	public static func create(ID: String)(tag: String)(draft: Bool)(prerelease: Bool)(assets: [Asset]) -> GitHubRelease {
		return self(ID: ID, tag: tag, draft: draft, prerelease: prerelease, assets: assets)
	}

	public static var decoder: JSONValue -> GitHubRelease? {
		return self.create
			<^> <|"id"
			<*> <|"tag_name"
			<*> <|"draft"
			<*> <|"prerelease"
			<*> <||"assets"
	}
}

/// Represents credentials suitable for logging in to GitHub.com.
internal struct GitHubCredentials {
	let username: String
	let password: String

	/// Returns the credentials encoded into a value suitable for the
	/// `Authorization` HTTP header.
	var authorizationHeaderValue: String {
		let data = "\(username):\(password)".dataUsingEncoding(NSUTF8StringEncoding)!
		let encodedString = data.base64EncodedStringWithOptions(nil)
		return "Basic \(encodedString)"
	}

	/// Attempts to load credentials from the Git credential store.
	static func loadFromGit() -> ColdSignal<GitHubCredentials?> {
		let data = "url=https://github.com".dataUsingEncoding(NSUTF8StringEncoding)!

		return launchGitTask([ "credential", "fill" ], standardInput: ColdSignal.single(data))
			.mergeMap { $0.linesSignal }
			.reduce(initial: [:]) { (var values: [String: String], line) in
				let parts = split(line, { $0 == "=" }, maxSplit: 1, allowEmptySlices: false)
				if parts.count >= 2 {
					let key = parts[0]
					let value = parts[1]

					values[key] = value
				}

				return values
			}
			.map { values -> GitHubCredentials? in
				if let username = values["username"] {
					if let password = values["password"] {
						return self(username: username, password: password)
					}
				}

				return nil
			}
	}
}

/// Creates a request to fetch the given GitHub URL, optionally authenticating
/// with the given credentials.
internal func createGitHubRequest(URL: NSURL, credentials: GitHubCredentials?) -> NSURLRequest {
	let request = NSMutableURLRequest(URL: URL)
	request.setValue(APIContentType, forHTTPHeaderField: "Accept")
	request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

	if let credentials = credentials {
		request.setValue(credentials.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
	}

	return request
}

/// Fetches all releases on the given repository, sending each along the
/// returned signal.
internal func releasesForRepository(repository: GitHubRepository, credentials: GitHubCredentials?) -> ColdSignal<GitHubRelease> {
	let request = createGitHubRequest(NSURL(string: "https://api.github.com/repos/\(repository.owner)/\(repository.name)/releases")!, credentials)

	// TODO: Automatically fetch additional pages.
	return NSURLSession.sharedSession()
		.rac_dataWithRequest(request)
		.map { data, _ in data }
		.tryMap { data, error -> NSArray? in
			return NSJSONSerialization.JSONObjectWithData(data, options: nil, error: error) as? NSArray
		}
		.mergeMap { releases -> ColdSignal<AnyObject> in
			return ColdSignal.fromValues(releases)
		}
		.concatMap { releaseDictionary -> ColdSignal<GitHubRelease> in
			if let release = GitHubRelease.decoder(JSONValue.parse(releaseDictionary)) {
				return .single(release)
			} else {
				return .empty()
			}
		}
}

/// Downloads the indicated release asset to a temporary file, returning the
/// URL to the file on disk.
internal func downloadAsset(asset: GitHubRelease.Asset, credentials: GitHubCredentials?) -> ColdSignal<NSURL> {
	let request = createGitHubRequest(asset.downloadURL, credentials)

	return NSURLSession.sharedSession()
		.rac_downloadWithRequest(request)
		.map { URL, _ in URL }
}
