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

/// Represents credentials suitable for logging in to GitHub.com.
internal struct GitHubCredentials {
	let username: String
	let password: String

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
