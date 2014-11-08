//
//  CarthageSpec.swift
//  Carthage
//
//  Created by Alan Rogers on 5/11/2014.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import Quick
import Nimble

class CarthageSpec: QuickSpec {
	var tempDirectoryPath: NSString!

	var repositoryFixturesPath: NSString {
		if (tempDirectoryPath == nil) {
			self.setUpTempDirectoryPath()
		}
		return self.tempDirectoryPath
	}

	func setUpTempDirectoryPath() {
		tempDirectoryPath = NSTemporaryDirectory().stringByAppendingPathComponent(NSUUID().UUIDString)

		let fileManager = NSFileManager.defaultManager()
		var error: NSError?
		let success = fileManager.createDirectoryAtPath(tempDirectoryPath!, withIntermediateDirectories:true, attributes:nil, error:&error)
		verify(success, "Couldn't create the temp fixtures directory at \(tempDirectoryPath): \(error)")
	}

	func setUpRepositoryFixtureIfNeeded(repositoryName: NSString) {
		let path = self.repositoryFixturesPath.stringByAppendingPathComponent(repositoryName)
		let fileManager = NSFileManager.defaultManager()

		var isDirectory: ObjCBool = false
		if (fileManager.fileExistsAtPath(path, isDirectory:&isDirectory) && isDirectory) {
			return
		}

		var error: NSError?
		var success = fileManager.createDirectoryAtPath(self.repositoryFixturesPath, withIntermediateDirectories:true, attributes:nil, error:&error)
		verify(success, "Couldn't create the repository fixtures directory at \(self.repositoryFixturesPath): \(error)")

		let zippedRepositoriesPath = NSBundle(forClass: self.dynamicType).resourcePath!.stringByAppendingPathComponent("fixtures").stringByAppendingPathComponent("repositories.zip")

		success = unzipFile(repositoryName, zipPath:zippedRepositoriesPath, destinationPath:self.repositoryFixturesPath)
		verify(success, "Couldn't unzip fixture \"\(repositoryName)\" from \(zippedRepositoriesPath) to \(self.repositoryFixturesPath)")
	}

	func pathForFixtureRepositoryNamed(repositoryName: String) -> NSURL {
		setUpRepositoryFixtureIfNeeded(repositoryName)
		return NSURL.fileURLWithPath("\(self.repositoryFixturesPath)/repositories/\(repositoryName)", isDirectory:true)!
	}

	func unzipFile(member: NSString, zipPath: NSString, destinationPath: NSString) -> Bool {
		let task = NSTask()
		task.launchPath = "/usr/bin/unzip"
		task.arguments = [ "-qq", "-d", destinationPath, zipPath, "repositories/\(member)*", "-x", "*/.DS_Store" ]

		task.launch()
		task.waitUntilExit()

		return task.terminationStatus == 0
	}
}