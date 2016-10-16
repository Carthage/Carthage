//
//  BuildVersion.swift
//  Carthage
//
//  Created by Rodrigo Garcia on 10/15/16.
//  Copyright © 2016 Carthage. All rights reserved.
//

import CarthageKit
import Commandant
import Foundation
import ReactiveCocoa
import ReactiveTask
import Result
import Tentacle

public struct CarthageVersion{
	
	public let localVersion:SemanticVersion
	public let remoteVersion:SemanticVersion
	
	public init (localVersion: SemanticVersion, remoteVersion:SemanticVersion){
		self.localVersion = localVersion
		self.remoteVersion = remoteVersion
	}
	
	func shouldUpgrade() ->Bool {
		
		if localVersion < remoteVersion {
			return true
		}
		
		return false
	}
}

func fetchLatestCarthageVersion() -> CarthageVersion{
	
	let versionString = NSBundle(identifier: CarthageKitBundleIdentifier)?.objectForInfoDictionaryKey("CFBundleShortVersionString") as! String
	
	let latestVersion = Client(.DotCom)
		.releasesInRepository(Repository(owner: "Carthage", name: "Carthage"), perPage: 1)
		.map { (_, releases) in
			return releases.first!
		}
		.mapError(CarthageError.GitHubAPIRequestFailed)
		.attemptMap { (release) -> Result<SemanticVersion, CarthageError> in
			return SemanticVersion.fromString(release.tag)
		}
		.timeoutWithError(CarthageError.GitHubAPITimeout, afterInterval: 0.1, onScheduler: QueueScheduler.mainQueueScheduler)
		.first()
	
	return CarthageVersion(localVersion: SemanticVersion.fromString(versionString).value!, remoteVersion: latestVersion!.value!)
}
