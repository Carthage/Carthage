import CarthageKit
import Foundation
import Nimble
import Quick
import ReactiveSwift

class ArchiveSpec: QuickSpec {
	override func spec() {
		describe("unzipping") {
			let archiveURL = Bundle(for: type(of: self)).url(forResource: "CartfilePrivateOnly", withExtension: "zip")!

			it("should unzip archive to a temporary directory") {
				let result = unarchive(archive: archiveURL).single()
				expect(result).notTo(beNil())
				expect(result?.error).to(beNil())

				let directoryPath = result?.value?.path ?? FileManager.default.currentDirectoryPath
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
			let path = (NSTemporaryDirectory() as NSString).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
			let temporaryURL = URL(fileURLWithPath: path, isDirectory: true)
			let archiveURL = temporaryURL.appendingPathComponent("archive.zip", isDirectory: false)

			beforeEach {
				expect { try FileManager.default.createDirectory(atPath: temporaryURL.path, withIntermediateDirectories: true, attributes: nil) }.notTo(throwError())
				expect(FileManager.default.changeCurrentDirectoryPath(temporaryURL.path)) == true
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

				let result = zip(paths: [ innerFilePath, outerFilePath ], into: archiveURL, workingDirectory: temporaryURL.path).wait()
				expect(result.error).to(beNil())

				let unzipResult = unarchive(archive: archiveURL).single()
				expect(unzipResult).notTo(beNil())
				expect(unzipResult?.error).to(beNil())

				let enumerationResult = FileManager.default.reactive
					.enumerator(at: unzipResult?.value ?? temporaryURL)
					.map { _, url in url }
					.map { $0.lastPathComponent }
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

				let result = zip(paths: [ symlinkPath, destinationPath ], into: archiveURL, workingDirectory: temporaryURL.path).wait()
				expect(result.error).to(beNil())

				let unzipResult = unarchive(archive: archiveURL).single()
				expect(unzipResult).notTo(beNil())
				expect(unzipResult?.error).to(beNil())

				let unzippedSymlinkURL = (unzipResult?.value ?? temporaryURL).appendingPathComponent(symlinkPath)
				expect(FileManager.default.fileExists(atPath: unzippedSymlinkURL.path)) == true
				expect { try FileManager.default.destinationOfSymbolicLink(atPath: unzippedSymlinkURL.path) } == destinationPath
			}
		}
	}
}
