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
import ReactiveCocoa

/// Locates Xcode projects or workspaces within the specified directory.
public struct LocateCommand: CommandType {
	public let verb = "locate"

	public func run(arguments: [String]) -> Result<()> {
		let path = first(arguments) ?? NSFileManager.defaultManager().currentDirectoryPath

		// TODO: Fail running if the path is invalid.
		let directoryURL = NSURL.fileURLWithPath(path)!

		return locateProjectsInDirectory(directoryURL)
			.on(next: { locator in
				switch (locator) {
				case let .Workspace(URL):
					println("Found an Xcode workspace at: \(URL.path!)")

				case let .ProjectFile(URL):
					println("Found an Xcode project at: \(URL.path!)")
				}
			})
			.then(ColdSignal<()>.empty())
			.wait()
	}
}
