//
//  GitSpec.swift
//  Carthage
//
//  Created by Alan Rogers on 3/11/2014.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import CarthageKit
import Quick

var tempDirectoryPath : NSString? = nil

func repositoryFixturesPath() -> NSString {
	return tempDirectoryPath().stringByAppendingPathComponent("repositories")
}

func setUpTempDirectoryPath() {
    tempDirectoryPath = NSTemporaryDirectory().stringByAppendingPathComponent(NSUUID())

    let fileManager = NSFileManager()
    let error : NSError? = nil;
    let success = fileManager.createDirectoryAtPath(tempDirectoryPath, withIntermediateDirectories:true, attributes:nil, error:&error);
    XCTAssertTrue(success, "Couldn't create the temp fixtures directory at %@: %@", tempDirectoryPath, error);
}

func setUpRepositoryFixtureIfNeeded(repositoryName: NSString) {
    let fixturesPath = repositoryFixturesPath()
    let path = fixturesPath.stringByAppendingPathComponent(repositoryName);

    let isDirectory = false;
    if (NSFileManager.defaultManager().fileExistsAtPath(path, isDirectory:&isDirectory) && isDirectory) {
        return
    }

    let error : NSError? = nil;
    let success = fileManager.createDirectoryAtPath(fixturesPath, withIntermediateDirectories:true, attributes:nil, error:&error);

    XCTAssertTrue(success, "Couldn't create the repository fixtures directory at %@: %@", fixturesPath, error);

    let zippedRepositoriesPath = mainTestBundle().resourcePath.stringByAppendingPathComponent("fixtures").stringByAppendingPathComponent("repositories.zip");

    error = nil;
    //success = unzipFile(repositoryName, fromArchiveAtPath:zippedRepositoriesPath, intoDirectory:fixturesPath error:&error);
    XCTAssertTrue(success, "Couldn't unzip fixture \"%@\" from %@ to %@: %@", repositoryName, zippedRepositoriesPath, self.repositoryFixturesPath, error);
}

func pathForFixtureRepositoryNamed(repositoryName: String) {
    setUpRepositoryFixtureIfNeeded(repositoryName)
    return repositoryFixturesPath.stringByAppendingPathComponent(repositoryName)
}

class GitSpec: QuickSpec {
    override func spec() {
        let archiveURL = NSBundle(forClass: self.dynamicType).URLForResource("repositories", withExtension: "zip", subdirectory: "fixtures")!

        beforeEach() {
            // unzip the repositories


        }

    }
}

