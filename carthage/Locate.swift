//
//  Locate.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import LlamaKit

struct LocateCommand: CommandType {
	static let verb = "locate"

	let directoryURL: NSURL

	init<C: CollectionType where C.Generator.Element == String>(_ arguments: C) {
		let path = first(arguments) ?? NSFileManager.defaultManager().currentDirectoryPath

		// TODO: Allow commands to fail initialization for cases like these.
		directoryURL = NSURL.fileURLWithPath(path)!
	}

	func run() -> Result<()> {
		let result = locateProjectInDirectory(directoryURL).first()

		switch (result) {
		case let .Success(locator):
			switch (locator.unbox) {
			case let .Workspace(URL):
				println("Found an Xcode workspace at: \(URL.path!)")

			case let .ProjectFile(URL):
				println("Found an Xcode project at: \(URL.path!)")
			}

			return success()

		case let .Failure(error):
			return failure(error)
		}
	}
}
