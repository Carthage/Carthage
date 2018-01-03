import Foundation
import CarthageKit
import ReactiveSwift
import ReactiveTask
import Result
import Tentacle

struct ExpirableVersion: Codable {
	let version: SemanticVersion?
	let expiredDate: Date

	init(version: SemanticVersion?, shelfLife: TimeInterval) {
		self.version = version
		self.expiredDate = Date(timeIntervalSinceNow: shelfLife)
	}

	init?(fromJSONData data: Data?) {
		guard let wrappedData = data, let wrapped = try? JSONDecoder().decode(ExpirableVersion.self, from: wrappedData) else {
			return nil
		}
		self = wrapped
	}

	func encodedJSONData() -> Data? {
		return try? JSONEncoder().encode(self)
	}

	var isExpired: Bool {
		return Date().compare(expiredDate) == ComparisonResult.orderedDescending
	}
}

/// The latest online version as a SemanticVersion object.
public func remoteVersion() -> SemanticVersion? {
	let userDefaults = UserDefaults.standard
	let cachedKey = "latestCarthageRemoteVersion"

	let expirableVersionData = userDefaults.data(forKey: cachedKey)
	let expirableVersion = ExpirableVersion(fromJSONData: expirableVersionData)

	guard expirableVersion == nil || expirableVersion!.isExpired else {
		return expirableVersion!.version
	}

	let latestRemoteVersion = Client(.dotCom)
		.execute(Repository(owner: "Carthage", name: "Carthage").releases, perPage: 2)
		.map { _, releases in
			return releases.first { !$0.isDraft }!
		}
		.mapError(CarthageError.gitHubAPIRequestFailed)
		.attemptMap { release -> Result<SemanticVersion, CarthageError> in
			return SemanticVersion.from(Scanner(string: release.tag)).mapError(CarthageError.init(scannableError:))
		}
		.timeout(after: 0.5, raising: CarthageError.gitHubAPITimeout, on: QueueScheduler.main)
		.first()

	// Expired after one day
	let latestExpirableVersion = ExpirableVersion(version: latestRemoteVersion?.value,
	                                              shelfLife: 24 * 60 * 60)
	if let encodedData = latestExpirableVersion.encodedJSONData() {
		userDefaults.set(encodedData, forKey: cachedKey)
	}
	return latestExpirableVersion.version
}
