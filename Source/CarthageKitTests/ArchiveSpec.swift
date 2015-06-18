//
//  ArchiveSpec.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2015-01-02.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import Nimble
import Quick
import ReactiveCocoa

class ArchiveSpec: QuickSpec {
	override func spec() {
		describe("unzipping") {
			let archiveURL = NSBundle(forClass: self.dynamicType).URLForResource("CartfilePrivateOnly", withExtension: "zip")!

			it("should unzip archive to a temporary directory") {
				let result = unzipArchiveToTemporaryDirectory(archiveURL) |> single
				expect(result).notTo(beNil())
				expect(result?.error).to(beNil())

				let directoryPath = result?.value?.path ?? NSFileManager.defaultManager().currentDirectoryPath
				var isDirectory: ObjCBool = false
				expect(NSFileManager.defaultManager().fileExistsAtPath(directoryPath, isDirectory: &isDirectory)).to(beTruthy())
				expect(isDirectory).to(beTruthy())

				let contents = NSFileManager.defaultManager().contentsOfDirectoryAtPath(directoryPath, error: nil) ?? []
				let innerFolderName = "CartfilePrivateOnly"
				expect(contents.isEmpty).to(beFalsy())
				expect(contents).to(contain(innerFolderName))

				let innerContents = NSFileManager.defaultManager().contentsOfDirectoryAtPath(directoryPath.stringByAppendingPathComponent(innerFolderName), error: nil) ?? []
				expect(innerContents.isEmpty).to(beFalsy())
				expect(innerContents).to(contain("Cartfile.private"))
			}
		}

		describe("zipping") {
			let originalCurrentDirectory = NSFileManager.defaultManager().currentDirectoryPath
			let temporaryURL = NSURL(fileURLWithPath: NSTemporaryDirectory().stringByAppendingPathComponent(NSProcessInfo.processInfo().globallyUniqueString), isDirectory: true)!
			let archiveURL = temporaryURL.URLByAppendingPathComponent("archive.zip", isDirectory: false)

			beforeEach {
				expect(NSFileManager.defaultManager().createDirectoryAtPath(temporaryURL.path!, withIntermediateDirectories: true, attributes: nil, error: nil)).to(beTruthy())
				expect(NSFileManager.defaultManager().changeCurrentDirectoryPath(temporaryURL.path!)).to(beTruthy())
				return
			}

			afterEach {
				NSFileManager.defaultManager().removeItemAtURL(temporaryURL, error: nil)
				expect(NSFileManager.defaultManager().changeCurrentDirectoryPath(originalCurrentDirectory)).to(beTruthy())
				return
			}

			it("should zip relative paths into an archive") {
				let subdirPath = "subdir"
				expect(NSFileManager.defaultManager().createDirectoryAtPath(subdirPath, withIntermediateDirectories: true, attributes: nil, error: nil)).to(beTruthy())

				let innerFilePath = subdirPath.stringByAppendingPathComponent("inner")
				expect("foobar".writeToFile(innerFilePath, atomically: true, encoding: NSUTF8StringEncoding, error: nil)).to(beTruthy())

				let outerFilePath = "outer"
				expect("foobar".writeToFile(outerFilePath, atomically: true, encoding: NSUTF8StringEncoding, error: nil)).to(beTruthy())

				let result = zipIntoArchive(archiveURL, [ innerFilePath, outerFilePath ]) |> wait
				expect(result.error).to(beNil())

				let unzipResult = unzipArchiveToTemporaryDirectory(archiveURL) |> single
				expect(unzipResult).notTo(beNil())
				expect(unzipResult?.error).to(beNil())

				let enumerationResult = NSFileManager.defaultManager().carthage_enumeratorAtURL(unzipResult?.value ?? temporaryURL, includingPropertiesForKeys: [], options: nil)
					|> map { enumerator, URL in URL }
					|> map { $0.lastPathComponent! }
					|> collect
					|> single

				expect(enumerationResult).notTo(beNil())
				expect(enumerationResult?.error).to(beNil())

				let fileNames = enumerationResult?.value
				expect(fileNames).to(contain("inner"))
				expect(fileNames).to(contain(subdirPath))
				expect(fileNames).to(contain(outerFilePath))
			}

			it("should preserve symlinks") {
				let destinationPath = "symlink-destination"
				expect("foobar".writeToFile(destinationPath, atomically: true, encoding: NSUTF8StringEncoding, error: nil)).to(beTruthy())

				let symlinkPath = "symlink"
				expect(NSFileManager.defaultManager().createSymbolicLinkAtPath(symlinkPath, withDestinationPath: destinationPath, error: nil)).to(beTruthy())
				expect(NSFileManager.defaultManager().destinationOfSymbolicLinkAtPath(symlinkPath, error: nil)).to(equal(destinationPath))

				let result = zipIntoArchive(archiveURL, [ symlinkPath, destinationPath ]) |> wait
				expect(result.error).to(beNil())

				let unzipResult = unzipArchiveToTemporaryDirectory(archiveURL) |> single
				expect(unzipResult).notTo(beNil())
				expect(unzipResult?.error).to(beNil())

				let unzippedSymlinkURL = (unzipResult?.value ?? temporaryURL).URLByAppendingPathComponent(symlinkPath)
				expect(NSFileManager.defaultManager().fileExistsAtPath(unzippedSymlinkURL.path!)).to(beTruthy())
				expect(NSFileManager.defaultManager().destinationOfSymbolicLinkAtPath(unzippedSymlinkURL.path!, error: nil)).to(equal(destinationPath))
			}
		}
	}
}
