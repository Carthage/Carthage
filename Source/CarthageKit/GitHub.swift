//
//  GitHub.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import Result
import ReactiveSwift
import Tentacle

/// The User-Agent to use for GitHub requests.
private func gitHubUserAgent() -> String {
	let bundle = Bundle.main

	let get: (_ key: String) -> String? = { bundle.object(forInfoDictionaryKey: $0) as? String }
	let version = get("CFBundleShortVersionString")
		?? get(kCFBundleVersionKey as String)
		?? "unknown"

	let identifier = bundle.bundleIdentifier
	return "\(identifier)/\(version)"
}

extension Repository {
	/// The URL that should be used for cloning this repository over HTTPS.
	public var httpsURL: GitURL {
		let auth = tokenFromEnvironment(forServer: server).map { "\($0)@" } ?? ""
		let scheme = server.url.scheme!

		return GitURL("\(scheme)://\(auth)\(server.url.host!)/\(owner)/\(name).git")
	}

	/// The URL that should be used for cloning this repository over SSH.
	public var sshURL: GitURL {
		return GitURL("ssh://git@\(server.url.host!)/\(owner)/\(name).git")
	}

	/// The URL for filing a new GitHub issue for this repository.
	public var newIssueURL: URL {
		return URL(string: "\(server)/\(owner)/\(name)/issues/new")!
	}
	
	/// Matches an identifier of the form "owner/name".
	private static let NWORegex = try! NSRegularExpression(pattern: "^([\\-\\.\\w]+)/([\\-\\.\\w]+)$", options: [])

	/// Parses repository information out of a string of the form "owner/name"
	/// for the github.com, or the form "http(s)://hostname/owner/name" for
	/// Enterprise instances.
	public static func fromIdentifier(_ identifier: String) -> Result<Repository, ScannableError> {
		// GitHub.com
		let range = NSRange(location: 0, length: identifier.utf16.count)
		if let match = NWORegex.firstMatch(in: identifier, range: range) {
			let owner = (identifier as NSString).substring(with: match.rangeAt(1))
			let name = (identifier as NSString).substring(with: match.rangeAt(2))
			return .success(self.init(owner: owner, name: strippingGitSuffix(name)))
		}

		// GitHub Enterprise
		breakpoint: if let url = URL(string: identifier), let host = url.host {
			var pathComponents = url.pathComponents.filter { $0 != "/" }
			guard pathComponents.count >= 2 else {
				break breakpoint
			}

			// Consider that the instance might be in subdirectories.
			let name = pathComponents.removeLast()
			let owner = pathComponents.removeLast()

			// If the host name starts with “github.com”, that is not an enterprise
			// one.
			if host == "github.com" || host == "www.github.com" {
				return .success(self.init(owner: owner, name: strippingGitSuffix(name)))
			} else {
				let baseURL = url.deletingLastPathComponent().deletingLastPathComponent()
				return .success(self.init(server: .enterprise(url: baseURL), owner: owner, name: strippingGitSuffix(name)))
			}
		}

		return .failure(ScannableError(message: "invalid GitHub repository identifier \"\(identifier)\""))
	}
}

extension Release {
	/// The name of this release, with fallback to its tag when the name is an empty string or nil.
	public var nameWithFallback: String {
		if let name = name, !name.isEmpty {
			return name
		}
		return tag
	}
}

private func credentialsFromGit(forServer server: Server) -> (String, String)? {
	let data = "url=\(server)".data(using: .utf8)!
	
	return launchGitTask([ "credential", "fill" ], standardInput: SignalProducer(value: data))
		.flatMap(.concat) { string in
			return string.linesProducer
		}
		.reduce([:]) { (values: [String: String], line: String) -> [String: String] in
			var values = values

			let parts = line.characters
				.split(maxSplits: 1, omittingEmptySubsequences: true) { $0 == "=" }
				.map(String.init)

			if parts.count >= 2 {
				let key = parts[0]
				let value = parts[1]
				
				values[key] = value
			}

			return values
		}
		.map { (values: [String: String]) -> (String, String)? in
			if let username = values["username"], let password = values["password"] {
				return (username, password)
			}
			
			return nil
		}
		.first()?
		.value ?? nil
}

private func tokenFromEnvironment(forServer server: Server) -> String? {
	let environment = ProcessInfo.processInfo.environment

	if let accessTokenInput = environment["GITHUB_ACCESS_TOKEN"] {
		// Treat the input as comma-separated series of domains and tokens.
		// (e.g., `GITHUB_ACCESS_TOKEN="github.com=XXXXXXXXXXXXX,enterprise.local/ghe=YYYYYYYYY"`)
		let records = accessTokenInput
			.characters
			.split(omittingEmptySubsequences: true) { $0 == "," }
			.reduce([:]) { (values: [String: String], record) in
				var values = values

				let parts = record.split(maxSplits: 1, omittingEmptySubsequences: true) { $0 == "=" }.map(String.init)
				switch parts.count {
				case 1:
					// If the input is provided as an access token itself, use the
					// token for Github.com.
					values["github.com"] = parts[0]

				case 2:
					let (server, token) = (parts[0], parts[1])
					values[server] = token

				default:
					break
				}

				return values
			}
		return records[server.url.host!]
	}
	
	return nil
}

extension Client {
	convenience init(repository: Repository, isAuthenticated: Bool = true) {
		if Client.userAgent == nil {
			Client.userAgent = gitHubUserAgent()
		}
		
		let server = repository.server
		
		if !isAuthenticated {
			self.init(server)
		} else if let token = tokenFromEnvironment(forServer: server) {
			self.init(server, token: token)
		} else if let (username, password) = credentialsFromGit(forServer: server) {
			self.init(server, username: username, password: password)
		} else {
			self.init(server)
		}
	}
	
}
