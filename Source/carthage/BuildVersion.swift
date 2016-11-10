//
//  BuildVersion.swift
//  Carthage
//
//  Created by Rodrigo Garcia on 10/15/16.
//  Copyright © 2016 Carthage. All rights reserved.
//

import Foundation
import CarthageKit
import ReactiveCocoa
import ReactiveTask
import Result
import Tentacle

public func localVersion() -> SemanticVersion {
	
	let versionString = NSBundle(identifier: CarthageKitBundleIdentifier)?.objectForInfoDictionaryKey("CFBundleShortVersionString") as! String
	return SemanticVersion.fromString(versionString).value!
}

public func remoteVersion() -> SemanticVersion? {
	
	let latestRemoteVersion = Client(.DotCom)
		.releasesInRepository(Repository(owner: "Carthage", name: "Carthage"), perPage: 1)
		.map { (_, releases) in
			return releases.first!
		}
		.mapError(CarthageError.gitHubAPIRequestFailed)
		.attemptMap { (release) -> Result<SemanticVersion, CarthageError> in
			return SemanticVersion.fromString(release.tag)
		}
		.timeoutWithError(CarthageError.gitHubAPITimeout, afterInterval: 0.5, onScheduler: QueueScheduler.mainQueueScheduler)
		.first()
	
	return latestRemoteVersion?.value
}
