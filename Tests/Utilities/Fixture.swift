//
//  Fixture.swift
//  Carthage
//
//  Created by J.D. Healy on 3/3/15.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa
import ReactiveTask

/// Zipped fixtures to test upon (usually once extracted to a temporary directory)
internal enum Fixture: String {
	case DependsOnPrelude = "DependsOnPrelude"

	var path: String {
		return bundle.pathForResource(self.rawValue, ofType: "zip")!
	}

	var URL: NSURL {
		return bundle.URLForResource(self.rawValue, withExtension: "zip")!
	}

	struct TemporaryDirectory {
		let URL: NSURL

		init(_ URL: NSURL) {
			self.URL = unzipArchiveToTemporaryDirectory(URL)
			// Append the sole directory of the temporary directory.
			.map { $0.URLByAppendingPathComponent(URL.URLByDeletingPathExtension!.lastPathComponent!) }
			// Iterate through dependencies directory and create Cartfile.
			.try { (URL: NSURL) -> Result<()> in
				var error: NSError?

				let subdirectories = NSFileManager.defaultManager().contentsOfDirectoryAtURL(
					URL.URLByAppendingPathComponent("dependencies"),
					includingPropertiesForKeys: nil,
					options: NSDirectoryEnumerationOptions.SkipsSubdirectoryDescendants,
					error: &error
				) as [NSURL]

				subdirectories.reduce( NSString() ) {
					previous, value in
					return previous + "git \"" + value.absoluteString! + "\"\n"
				}.writeToURL(
					URL.URLByAppendingPathComponent("Cartfile"),
					atomically: false,
					encoding: NSUTF8StringEncoding,
					error: &error
				)

				if let error = error {
					return Error.failure(description: error.description)
				} else {
					return success()
				}
			}
			.try { (URL: NSURL) -> Result<String> in
				return CLI.Git.launch(
					arguments: ["add", "--all"],
					workingDirectoryPath: URL.path!
				).single()
			}.try { (URL: NSURL) -> Result<String> in
				return CLI.Git.launch(
					arguments: ["commit", "-m", "Add Cartfile."],
					workingDirectoryPath: URL.path!
				).single()
			}.on(error: {
				fatalError($0.description)
			}).single().value()!
		}

		var path: String {
			return self.URL.path!
		}
	}

	var temporaryDirectory: TemporaryDirectory {
		return TemporaryDirectory(self.URL)
	}
}
