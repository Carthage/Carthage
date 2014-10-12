//
//  Build.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import LlamaKit
import ReactiveCocoa

struct BuildCommand: CommandType {
	static let verb = "build"

	let directoryURL: NSURL

	// TODO: Support -configuration argument
	init(_ arguments: [String] = []) {
		directoryURL = NSURL.fileURLWithPath(NSFileManager.defaultManager().currentDirectoryPath)!
	}

	func run() -> Result<()> {
		return buildInDirectory(directoryURL).await()
	}
}
