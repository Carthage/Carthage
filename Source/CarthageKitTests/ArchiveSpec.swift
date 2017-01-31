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
#if swift(>=3)
import ReactiveSwift
#else
import ReactiveCocoa
#endif

#if swift(>=3)
#else
	internal func type<T>(of t: T) -> T.Type {
		return t.dynamicType
	}
#endif

class ArchiveSpec: QuickSpec {
	override func spec() {
		describe("unzipping") {
			let archiveURL = Bundle(for: type(of: self)).url(forResource: "CartfilePrivateOnly", withExtension: "zip")!

			it("should unzip archive to a temporary directory") {
				let result = unzip(archive: archiveURL).single()
				expect(result).notTo(beNil())
				expect(result?.error).to(beNil())

				let directoryPath = result?.value?.carthage_path ?? FileManager.default.currentDirectoryPath
				expect(directoryPath).to(beExistingDirectory())

				let contents = (try? FileManager.default.contentsOfDirectory(atPath: directoryPath)) ?? []
				let innerFolderName = "CartfilePrivateOnly"
				expect(contents.isEmpty) == false
				expect(contents).to(contain(innerFolderName))

				let innerContents = (try? FileManager.default.contentsOfDirectory(atPath: (directoryPath as NSString).appendingPathComponent(innerFolderName))) ?? []
				expect(innerContents.isEmpty) == false
				expect(innerContents).to(contain("Cartfile.private"))
			}
		}

		describe("zipping") {
			let originalCurrentDirectory = FileManager.default.currentDirectoryPath
			let temporaryURL = URL(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString), isDirectory: true)
			let archiveURL = temporaryURL.appendingPathComponent("archive.zip", isDirectory: false)

			beforeEach {
				expect { try FileManager.default.createDirectory(atPath: temporaryURL.carthage_path, withIntermediateDirectories: true, attributes: nil) }.notTo(throwError())
				expect(FileManager.default.changeCurrentDirectoryPath(temporaryURL.carthage_path)) == true
				return
			}

			afterEach {
				_ = try? FileManager.default.removeItem(at: temporaryURL)
				expect(FileManager.default.changeCurrentDirectoryPath(originalCurrentDirectory)) == true
				return
			}

			it("should zip relative paths into an archive") {
				let subdirPath = "subdir"
				expect { try FileManager.default.createDirectory(atPath: subdirPath, withIntermediateDirectories: true) }.notTo(throwError())

				let innerFilePath = (subdirPath as NSString).appendingPathComponent("inner")
				expect { try "foobar".write(toFile: innerFilePath, atomically: true, encoding: .utf8) }.notTo(throwError())

				let outerFilePath = "outer"
				expect { try "foobar".write(toFile: outerFilePath, atomically: true, encoding: .utf8) }.notTo(throwError())

				let result = zip(paths: [ innerFilePath, outerFilePath ], into: archiveURL, workingDirectory: temporaryURL.carthage_path).wait()
				expect(result.error).to(beNil())

				let unzipResult = unzip(archive: archiveURL).single()
				expect(unzipResult).notTo(beNil())
				expect(unzipResult?.error).to(beNil())

				let enumerationResult = FileManager.default.carthage_enumerator(at: unzipResult?.value ?? temporaryURL)
					.map { enumerator, url in url }
					.map { $0.carthage_lastPathComponent }
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
				expect { try "foobar".write(toFile: destinationPath, atomically: true, encoding: .utf8) }.notTo(throwError())

				let symlinkPath = "symlink"
				expect { try FileManager.default.createSymbolicLink(atPath: symlinkPath, withDestinationPath: destinationPath) }.notTo(throwError())
				expect { try FileManager.default.destinationOfSymbolicLink(atPath: symlinkPath) } == destinationPath
				
				let result = zip(paths: [ symlinkPath, destinationPath ], into: archiveURL, workingDirectory: temporaryURL.carthage_path).wait()
				expect(result.error).to(beNil())

				let unzipResult = unzip(archive: archiveURL).single()
				expect(unzipResult).notTo(beNil())
				expect(unzipResult?.error).to(beNil())

				let unzippedSymlinkURL = (unzipResult?.value ?? temporaryURL).appendingPathComponent(symlinkPath)
				expect(FileManager.default.fileExists(atPath: unzippedSymlinkURL.carthage_path)) == true
				expect { try FileManager.default.destinationOfSymbolicLink(atPath: unzippedSymlinkURL.carthage_path) } == destinationPath
			}
		}
	}
}
