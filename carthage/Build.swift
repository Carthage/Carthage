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
	let verb = "build"

	func run<C: CollectionType where C.Generator.Element == String>(arguments: C) -> ColdSignal<()> {
		// TODO: Support -configuration argument
		let directoryURL = NSURL.fileURLWithPath(NSFileManager.defaultManager().currentDirectoryPath)!

		return buildInDirectory(directoryURL)
	}
}
