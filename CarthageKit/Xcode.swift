//
//  Xcode.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa

public func buildInDirectory(directoryURL: NSURL, configuration: String = "Release") -> Promise<Result<()>> {
	precondition(directoryURL.fileURL)

	let directoryPath = directoryURL.path
	let desc = TaskDescription(launchPath: "/usr/bin/xcrun", arguments: [ "xcodebuild", "build" ], workingDirectoryPath: directoryPath)

	return launchTask(desc).then { status in
		return Promise { sink in
			if status == EXIT_SUCCESS {
				sink.put(success())
			} else {
				sink.put(failure())
			}
		}
	}
}
