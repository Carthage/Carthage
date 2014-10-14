//
//  Git.swift
//  Carthage
//
//  Created by Alan Rogers on 14/10/2014.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit

public func cloneDependency(dependency: Dependency, destinationURL: NSURL) -> Result<()> {
    let destinationPath = destinationURL.URLByAppendingPathComponent("\(dependency.repository.name)-\(dependency.version)").path!

    let arguments = [
        "clone",
        "--depth=1",
        dependency.repository.cloneURL.absoluteString!,
        destinationPath,
    ]

    let taskDescription = TaskDescription(launchPath: "/usr/bin/git", arguments: arguments)
    let promise = launchTask(taskDescription)

    let exitStatus = promise.await()

    if exitStatus < 0 {
        return failure()
    }
    return success()
}
