//
//  Extensions.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-26.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

// This file contains extensions to anything that's not appropriate for
// CarthageKit.

import CarthageKit
import Commandant
import Foundation
import LlamaKit
import ReactiveCocoa

private let outputQueue = { () -> dispatch_queue_t in
	let queue = dispatch_queue_create("org.carthage.carthage.outputQueue", DISPATCH_QUEUE_SERIAL)
	dispatch_set_target_queue(queue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0))

	atexit_b {
		dispatch_barrier_sync(queue) {}
	}

	return queue
}()

/// A thread-safe version of Swift's standard println().
internal func println() {
	dispatch_async(outputQueue) {
		Swift.println()
	}
}

/// A thread-safe version of Swift's standard println().
internal func println<T>(object: T) {
	dispatch_async(outputQueue) {
		Swift.println(object)
	}
}

/// A thread-safe version of Swift's standard print().
internal func print<T>(object: T) {
	dispatch_async(outputQueue) {
		Swift.print(object)
	}
}

extension GitURL: ArgumentType {
	public static let name = "URL"

	public static func fromString(string: String) -> GitURL? {
		return self(string)
	}
}

/// Logs project events put into the sink.
internal struct ProjectEventSink: SinkType {
	private let colorOptions: ColorOptions
	
	init(colorOptions: ColorOptions) {
		self.colorOptions = colorOptions
	}
	
	mutating func put(event: ProjectEvent) {
		let formatting = colorOptions.formatting
		
		switch event {
		case let .Cloning(project):
			carthage.println(formatting.bullets + "Cloning " + formatting.projectName(string: project.name))

		case let .Fetching(project):
			carthage.println(formatting.bullets + "Fetching " + formatting.projectName(string: project.name))

		case let .CheckingOut(project, revision):
			carthage.println(formatting.bullets + "Checking out " + formatting.projectName(string: project.name) + " at " + formatting.quote(revision))

		case let .DownloadingBinaries(project, release):
			carthage.println(formatting.bullets + "Downloading " + formatting.projectName(string: project.name) + " at " + formatting.quote(release))
		}
	}
}

extension Project {
	/// Determines whether the project needs to be migrated from an older
	/// Carthage version, then performs the work if so.
	///
	/// If migration is necessary, sends one or more output lines describing the
	/// process to the user.
	internal func migrateIfNecessary(colorOptions: ColorOptions) -> ColdSignal<String> {
		let directoryPath = settings.directoryURL.path!
		let fileManager = NSFileManager.defaultManager()

		// These don't need to be declared more globally, since they're only for
		// migration. We shouldn't need these names anywhere else.
		let cartfileLock = "Cartfile.lock"
		let carthageBuild = "Carthage.build"
		let carthageCheckout = "Carthage.checkout"
		
		let formatting = colorOptions.formatting
		
		let migrationMessage = formatting.bulletinTitle("MIGRATION WARNING") + "\n\nThis project appears to be set up for an older (pre-0.4) version of Carthage. Unfortunately, the directory structure for Carthage projects has since changed, so this project will be migrated automatically.\n\nSpecifically, the following renames will occur:\n\n  \(cartfileLock) -> \(CarthageProjectResolvedCartfilePath)\n  \(carthageBuild) -> \(CarthageBinariesFolderPath)\n  \(carthageCheckout) -> \(CarthageProjectCheckoutsPath)\n\nFor more information, see " + formatting.URL(string: "https://github.com/Carthage/Carthage/pull/224") + ".\n"
		let signals = ColdSignal<ColdSignal<String>> { sink, disposable in
			let checkFile: (String, String) -> () = { oldName, newName in
				if fileManager.fileExistsAtPath(directoryPath.stringByAppendingPathComponent(oldName)) {
					let signal = ColdSignal<String>.single(migrationMessage)
						.concat(moveItemInPossibleRepository(self.settings.directoryURL, fromPath: oldName, toPath: newName).then(.empty()))

					sink.put(.Next(Box(signal)))
				}
			}

			checkFile(cartfileLock, CarthageProjectResolvedCartfilePath)
			checkFile(carthageBuild, CarthageBinariesFolderPath)

			// Carthage.checkout has to be handled specially, because if it
			// includes submodules, we need to move them one-by-one to ensure
			// that .gitmodules is properly updated.
			if fileManager.fileExistsAtPath(directoryPath.stringByAppendingPathComponent(carthageCheckout)) {
				let oldCheckoutsURL = self.settings.directoryURL.URLByAppendingPathComponent(carthageCheckout)

				var error: NSError?
				if let contents = fileManager.contentsOfDirectoryAtURL(oldCheckoutsURL, includingPropertiesForKeys: nil, options: NSDirectoryEnumerationOptions.SkipsSubdirectoryDescendants | NSDirectoryEnumerationOptions.SkipsPackageDescendants | NSDirectoryEnumerationOptions.SkipsHiddenFiles, error: &error) {
					let trashSignal = ColdSignal<()>.lazy {
						var error: NSError?
						if fileManager.trashItemAtURL(oldCheckoutsURL, resultingItemURL: nil, error: &error) {
							return .empty()
						} else {
							return .error(error ?? CarthageError.WriteFailed(oldCheckoutsURL).error)
						}
					}

					let moveSignals: ColdSignal<()> = ColdSignal.fromValues(contents)
						.map { (object: AnyObject) in object as NSURL }
						.concatMap { (URL: NSURL) -> ColdSignal<NSURL> in
							let lastPathComponent: String! = URL.lastPathComponent
							return moveItemInPossibleRepository(self.settings.directoryURL, fromPath: carthageCheckout.stringByAppendingPathComponent(lastPathComponent), toPath: CarthageProjectCheckoutsPath.stringByAppendingPathComponent(lastPathComponent))
						}
						.then(trashSignal)

					let signal = ColdSignal<String>.single(migrationMessage)
						.concat(moveSignals.then(.empty()))

					sink.put(.Next(Box(signal)))
				} else {
					sink.put(.Error(error ?? CarthageError.ReadFailed(oldCheckoutsURL).error))
					return
				}
			}

			sink.put(.Completed)
		}

		return signals.concat(identity).takeLast(1)
	}
}
