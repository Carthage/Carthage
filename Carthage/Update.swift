//
//  Update.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-12.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa
import CarthageKit

public struct UpdateCommand: CommandType {
	public let verb = "update"
	public let function = "Clone, check out, and build the dependencies in the project's Cartfile"

	public func run(mode: CommandMode) -> Result<()> {
		let directoryURL = NSURL.fileURLWithPath(NSFileManager.defaultManager().currentDirectoryPath)!

		return ColdSignal.fromResult(Project.loadFromDirectory(directoryURL))
			.map(updatedDependenciesForProject)
			.merge(identity)
			.on(next: { cartfileLock in
				println("Cartfile.lock:\n\(cartfileLock)")
			})
			.wait()
	}
}
