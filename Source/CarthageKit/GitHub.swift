//
//  GitHub.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa

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

public struct GitHubRelease: Equatable {
	public let ID: String
	public let tag: String
	public let draft: Bool
	public let prerelease: Bool
	public let assets: [Asset]

	public struct Asset: Equatable, Hashable, Printable {
		public let ID: String
		public let name: String
		public let contentType: String
		public let downloadURL: NSURL

		public var hashValue: Int {
			return ID.hashValue
		}

		public var description: String {
			return "Asset { name = \(name), contentType = \(contentType), downloadURL = \(downloadURL) }"
		}

		public init?(JSONDictionary: NSDictionary) {
			if let ID: AnyObject = JSONDictionary["id"] {
				self.ID = toString(ID)
			} else {
				return nil
			}

			if let name = JSONDictionary["name"] as? String {
				self.name = name
			} else {
				return nil
			}

			if let contentType = JSONDictionary["content_type"] as? String {
				self.contentType = contentType
			} else {
				return nil
			}

			if let downloadURLString = JSONDictionary["browser_download_url"] as? String {
				if let downloadURL = NSURL(string: downloadURLString) {
					self.downloadURL = downloadURL
				} else {
					return nil
				}
			} else {
				return nil
			}
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
	///
	/// If valid credentials are found, they are sent. Otherwise, the returned
	/// signal will be empty.
	static func loadFromGit() -> ColdSignal<GitHubCredentials> {
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
			.tryMap { (values, _) -> GitHubCredentials? in
				if let username = values["username"] {
					if let password = values["password"] {
						return self(username: username, password: password)
					}
				}

				return nil
			}
			.catch { _ in .empty() }
	}
}
