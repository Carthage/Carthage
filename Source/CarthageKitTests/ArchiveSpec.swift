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
				let result = unzipArchiveToTemporaryDirectory(archiveURL).single()
				expect(result).notTo(beNil())
				expect(result?.error).to(beNil())

				let directoryPath = result?.value?.path ?? NSFileManager.defaultManager().currentDirectoryPath
				var isDirectory: ObjCBool = false
				expect(NSFileManager.defaultManager().fileExistsAtPath(directoryPath, isDirectory: &isDirectory)) == true
				expect(isDirectory) == true

				let contents = (try? NSFileManager.defaultManager().contentsOfDirectoryAtPath(directoryPath)) ?? []
				let innerFolderName = "CartfilePrivateOnly"
				expect(contents.isEmpty) == false
				expect(contents).to(contain(innerFolderName))

				let innerContents = (try? NSFileManager.defaultManager().contentsOfDirectoryAtPath((directoryPath as NSString).stringByAppendingPathComponent(innerFolderName))) ?? []
				expect(innerContents.isEmpty) == false
				expect(innerContents).to(contain("Cartfile.private"))
			}
		}

		describe("zipping") {
			let originalCurrentDirectory = NSFileManager.defaultManager().currentDirectoryPath
			let temporaryURL = NSURL(fileURLWithPath: (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent(NSProcessInfo.processInfo().globallyUniqueString), isDirectory: true)
			let archiveURL = temporaryURL.URLByAppendingPathComponent("archive.zip", isDirectory: false)

			beforeEach {
				expect { try NSFileManager.defaultManager().createDirectoryAtPath(temporaryURL.path!, withIntermediateDirectories: true, attributes: nil) }.notTo(throwError())
				expect(NSFileManager.defaultManager().changeCurrentDirectoryPath(temporaryURL.path!)) == true
				return
			}

			afterEach {
				_ = try? NSFileManager.defaultManager().removeItemAtURL(temporaryURL)
				expect(NSFileManager.defaultManager().changeCurrentDirectoryPath(originalCurrentDirectory)) == true
				return
			}

			it("should zip relative paths into an archive") {
				let subdirPath = "subdir"
				expect { try NSFileManager.defaultManager().createDirectoryAtPath(subdirPath, withIntermediateDirectories: true, attributes: nil) }.notTo(throwError())

				let innerFilePath = (subdirPath as NSString).stringByAppendingPathComponent("inner")
				expect { try "foobar".writeToFile(innerFilePath, atomically: true, encoding: NSUTF8StringEncoding) }.notTo(throwError())

				let outerFilePath = "outer"
				expect { try "foobar".writeToFile(outerFilePath, atomically: true, encoding: NSUTF8StringEncoding) }.notTo(throwError())

				let result = zipIntoArchive(archiveURL, [ innerFilePath, outerFilePath ]).wait()
				expect(result.error).to(beNil())

				let unzipResult = unzipArchiveToTemporaryDirectory(archiveURL).single()
				expect(unzipResult).notTo(beNil())
				expect(unzipResult?.error).to(beNil())

				let enumerationResult = NSFileManager.defaultManager().carthage_enumeratorAtURL(unzipResult?.value ?? temporaryURL, includingPropertiesForKeys: [], options: [])
					.map { enumerator, URL in URL }
					.map { $0.lastPathComponent! }
					.collect()
					.single()

				expect(enumerationResult).notTo(beNil())
				expect(enumerationResult?.error).to(beNil())

				let fileNames = enumerationResult?.value
				expect(fileNames).to(contain("inner"))
				expect(fileNames).to(contain(subdirPath))
				expect(fileNames).to(contain(outerFilePath))
			}

			it("should preserve symlinks") {
				let destinationPath = "symlink-destination"
				expect { try "foobar".writeToFile(destinationPath, atomically: true, encoding: NSUTF8StringEncoding) }.notTo(throwError())

				let symlinkPath = "symlink"
				expect { try NSFileManager.defaultManager().createSymbolicLinkAtPath(symlinkPath, withDestinationPath: destinationPath) }.notTo(throwError())
				expect { try NSFileManager.defaultManager().destinationOfSymbolicLinkAtPath(symlinkPath) } == destinationPath

				let result = zipIntoArchive(archiveURL, [ symlinkPath, destinationPath ]).wait()
				expect(result.error).to(beNil())

				let unzipResult = unzipArchiveToTemporaryDirectory(archiveURL).single()
				expect(unzipResult).notTo(beNil())
				expect(unzipResult?.error).to(beNil())

				let unzippedSymlinkURL = (unzipResult?.value ?? temporaryURL).URLByAppendingPathComponent(symlinkPath)
				expect(NSFileManager.defaultManager().fileExistsAtPath(unzippedSymlinkURL.path!)) == true
				expect { try NSFileManager.defaultManager().destinationOfSymbolicLinkAtPath(unzippedSymlinkURL.path!) } == destinationPath
			}
		}
	}
}
