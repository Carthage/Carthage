import Foundation
import CarthageKit
import ReactiveSwift
import ReactiveTask
import Result
import Tentacle
import Utility

/// The latest version of Carthage as a `Version`.
public func remoteVersion() -> Version? {
	let remoteVersionProducer = Client(.dotCom, urlSession: URLSession.proxiedSession)
		.execute(Repository(owner: "Carthage", name: "Carthage").releases, perPage: 2)
		.mapError(CarthageError.gitHubAPIRequestFailed)
		.filterMap { _, releases in
			return releases.first { !$0.isDraft }
		}
	return remoteVersion(remoteVersionProducer)
}
