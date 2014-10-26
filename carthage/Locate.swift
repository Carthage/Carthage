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

	public func run(mode: CommandMode) -> Result<()> {
		return ColdSignal.fromResult(LocateOptions.evaluate(mode))
			.map { options -> ColdSignal<ProjectLocator> in
				// TODO: Fail running if the path is invalid.
				let directoryURL = NSURL.fileURLWithPath(options.path)!

				return locateProjectsInDirectory(directoryURL)
			}
			.merge(identity)
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

private struct LocateOptions: OptionsType {
	let path: String

	static func create(var path: String) -> LocateOptions {
		if path == "" {
			path = NSFileManager.defaultManager().currentDirectoryPath
		}

		return self(path: path)
	}

	static func evaluate(m: CommandMode) -> Result<LocateOptions> {
		return create
			<*> m <| option(defaultValue: "", "the directory in which to look for Xcode projects")
	}
}
