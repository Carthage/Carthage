import Foundation
import CarthageKit
import ReactiveSwift
import ReactiveTask
import Result
import Tentacle

/// The latest online version as a SemanticVersion object.
public func remoteVersion() -> SemanticVersion? {
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

	return latestRemoteVersion?.value
}
