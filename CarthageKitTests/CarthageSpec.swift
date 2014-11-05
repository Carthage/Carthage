//
//  CarthageSpec.swift
//  Carthage
//
//  Created by Alan Rogers on 5/11/2014.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import Quick

class CarthageSpec: QuickSpec {
    var tempDirectoryPath: NSString!

    var repositoryFixturesPath: NSString {
        if (tempDirectoryPath == nil) {
            self.setUpTempDirectoryPath()
        }
        return self.tempDirectoryPath.stringByAppendingPathComponent("repositories")
    }

    func setUpTempDirectoryPath() {
        tempDirectoryPath = NSTemporaryDirectory().stringByAppendingPathComponent(NSUUID().UUIDString)

        let fileManager = NSFileManager.defaultManager()
        var error: NSError?
        let success = fileManager.createDirectoryAtPath(tempDirectoryPath!, withIntermediateDirectories:true, attributes:nil, error:&error)
        XCTAssertTrue(success, "Couldn't create the temp fixtures directory at \(tempDirectoryPath): \(error)")
    }

    func setUpRepositoryFixtureIfNeeded(repositoryName: NSString) {
        let path = self.repositoryFixturesPath.stringByAppendingPathComponent(repositoryName)
        let fileManager = NSFileManager.defaultManager()

        var isDirectory: ObjCBool = false
        if (fileManager.fileExistsAtPath(path, isDirectory:&isDirectory) && isDirectory) {
            return
        }

        var error: NSError?
        let success = fileManager.createDirectoryAtPath(self.repositoryFixturesPath, withIntermediateDirectories:true, attributes:nil, error:&error)
        XCTAssertTrue(success, "Couldn't create the repository fixtures directory at \(self.repositoryFixturesPath): \(error)")

        let zippedRepositoriesPath = NSBundle(forClass: self.dynamicType).resourcePath!.stringByAppendingPathComponent("fixtures").stringByAppendingPathComponent("repositories.zip")

        error = nil
        //success = unzipFile(repositoryName, fromArchiveAtPath:zippedRepositoriesPath, intoDirectory:fixturesPath error:&error);
        XCTAssertTrue(success, "Couldn't unzip fixture \"\(repositoryName)\" from \(zippedRepositoriesPath) to \(self.repositoryFixturesPath): \(error)")
    }

    func pathForFixtureRepositoryNamed(repositoryName: String) -> NSString {
        setUpRepositoryFixtureIfNeeded(repositoryName)
        return self.repositoryFixturesPath.stringByAppendingPathComponent(repositoryName)
    }
}