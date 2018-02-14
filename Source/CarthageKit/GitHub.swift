import Foundation
import Result
import ReactiveSwift
import Tentacle

/// The User-Agent to use for GitHub requests.
private func gitHubUserAgent() -> String {
	let identifier = Constants.bundleIdentifier
	let version = CarthageKitVersion.current.value
	return "\(identifier)/\(version)"
}

extension Server {
	/// The URL that should be used for cloning the given repository over HTTPS.
	public func httpsURL(for repository: Repository) -> GitURL {
		let auth = tokenFromEnvironment(forServer: self).map { "\($0)@" } ?? ""
		let scheme = url.scheme!

		return GitURL("\(scheme)://\(auth)\(url.host!)/\(repository.owner)/\(repository.name).git")
	}

	/// The URL that should be used for cloning the given repository over SSH.
	public func sshURL(for repository: Repository) -> GitURL {
		return GitURL("ssh://git@\(url.host!)/\(repository.owner)/\(repository.name).git")
	}

	/// The URL for filing a new GitHub issue for the given repository.
	public func newIssueURL(for repository: Repository) -> URL {
		return URL(string: "\(self)/\(repository.owner)/\(repository.name)/issues/new")!
	}
}

extension Repository {
	/// Matches an identifier of the form "owner/name".
	private static let nwoRegex = try! NSRegularExpression(pattern: "^([\\-\\.\\w]+)/([\\-\\.\\w]+)$", options: []) // swiftlint:disable:this force_try

	/// Parses repository information out of a string of the form "owner/name"
	/// for the github.com, or the form "http(s)://hostname/owner/name" for
	/// Enterprise instances.
	public static func fromIdentifier(_ identifier: String) -> Result<(Server, Repository), ScannableError> {
		// ‘owner/name’ → GitHub.com
		let range = NSRange(identifier.startIndex..., in: identifier)
		if let match = nwoRegex.firstMatch(in: identifier, range: range) {
			let owner = String(identifier[Range(match.range(at: 1), in: identifier)!])
			let name = String(identifier[Range(match.range(at: 2), in: identifier)!])
			return .success((.dotCom, self.init(owner: owner, name: strippingGitSuffix(name))))
		}

		// Hostname-based → GitHub Enterprise
		guard
			let url = URL(string: identifier),
			let host = url.host,
			case var pathComponents = url.pathComponents.filter({ $0 != "/" }),
			pathComponents.count >= 2,
			case (let name, let owner) = (pathComponents.removeLast(), pathComponents.removeLast())
		else {
			return .failure(ScannableError(message: "invalid GitHub repository identifier \"\(identifier)\""))
		}

		// If the host name starts with “github.com”, that is not an enterprise
		// one.
		guard host != "github.com", host != "www.github.com" else {
			return .success((.dotCom, self.init(owner: owner, name: strippingGitSuffix(name))))
		}

		let baseURL = url.deletingLastPathComponent().deletingLastPathComponent()
		return .success((.enterprise(url: baseURL), self.init(owner: owner, name: strippingGitSuffix(name))))
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
		.reduce(into: [:]) { (values: inout [String: String], line: String) in
			let parts = line
				.split(maxSplits: 1, omittingEmptySubsequences: true) { $0 == "=" }
				.map(String.init)

			if parts.count >= 2 {
				let key = parts[0]
				let value = parts[1]

				values[key] = value
			}
		}
		.map { (values: [String: String]) -> (String, String)? in
			if let username = values["username"], let password = values["password"] {
				return (username, password)
			}

			return nil
		}
		.first()?
		.value ?? nil // swiftlint:disable:this redundant_nil_coalescing
}

private func tokenFromEnvironment(forServer server: Server) -> String? {
	let environment = ProcessInfo.processInfo.environment

	if let accessTokenInput = environment["GITHUB_ACCESS_TOKEN"] {
		// Treat the input as comma-separated series of domains and tokens.
		// (e.g., `GITHUB_ACCESS_TOKEN="github.com=XXXXXXXXXXXXX,enterprise.local/ghe=YYYYYYYYY"`)
		let records = accessTokenInput
			.split(omittingEmptySubsequences: true) { $0 == "," }
			.reduce(into: [:]) { (values: inout [String: String], record) in
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
			}
		return records[server.url.host!]
	}

	return nil
}

extension Client {
	convenience init(server: Server, isAuthenticated: Bool = true) {
		if Client.userAgent == nil {
			Client.userAgent = gitHubUserAgent()
		}

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
