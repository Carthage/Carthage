import Foundation
import Quick
import Nimble
import ReactiveSwift
import Result
import XCDBLD
@testable import CarthageKit

class VersionFileSpec: QuickSpec {
	override func spec() {
		it("should read a version file correctly") {
            guard let versionFileURL = Bundle(for: type(of: self)).url(forResource: "TestVersionFile", withExtension: "") else {
                fail("Could not load TestVersionFile from resources")
                return
            }
            guard let versionFile = VersionFile(url: versionFileURL) else {
                fail("Expected version file to not be nil")
                return
            }
			expect(versionFile.commitish) == "v1.0"

			// Check multiple frameworks
			let iOSCache = versionFile.iOS
			expect(iOSCache).notTo(beNil())
			expect(iOSCache?.count) == 2
			expect(iOSCache?[0].name) == "TestFramework1"
			expect(iOSCache?[0].hash) == "ios-framework1-hash"
			expect(iOSCache?[0].swiftToolchainVersion) == "4.2 (swiftlang-1000.11.37.1 clang-1000.11.45.1)"
			expect(iOSCache?[1].name) == "TestFramework2"
			expect(iOSCache?[1].hash) == "ios-framework2-hash"
			expect(iOSCache?[1].swiftToolchainVersion) == "4.2.1 (swiftlang-1000.11.42 clang-1000.11.45.1)"

			// Check different number of frameworks for a platform
			let macOSCache = versionFile.macOS
			expect(macOSCache).notTo(beNil())
			expect(macOSCache?.count) == 1
			expect(macOSCache?[0].name) == "TestFramework1"
			expect(macOSCache?[0].hash) == "mac-framework1-hash"
			expect(iOSCache?[0].swiftToolchainVersion) == "4.2 (swiftlang-1000.11.37.1 clang-1000.11.45.1)"

			// Check empty framework list
			let tvOSCache = versionFile.tvOS
			expect(tvOSCache).notTo(beNil())
			expect(tvOSCache?.count) == 0

			// Check missing platform
			let watchOSCache = versionFile.watchOS
			expect(watchOSCache).to(beNil())
		}

		it("should write and read back a version file correctly") {
			let framework = CachedFramework(name: "TestFramework",
							hash: "TestHASH",
							swiftToolchainVersion: "4.2 (swiftlang-1000.11.37.1 clang-1000.11.45.1)")
			let versionFile = VersionFile(commitish: "v1.0",
						      macOS: nil,
						      iOS: [framework],
						      watchOS: nil,
						      tvOS: nil)

            guard let versionFileURL = Bundle(for: type(of: self)).resourceURL?.appendingPathComponent("TestWriteVersionFile") else {
                fail("Expected resource URL to not be nil")
                return
            }

			let result = versionFile.write(to: versionFileURL)

			expect(result.error).to(beNil())

			expect(FileManager.default.fileExists(atPath: versionFileURL.path)).to(beTrue())

			let newVersionFile = VersionFile(url: versionFileURL)
			expect(newVersionFile).notTo(beNil())

			expect(newVersionFile?.commitish) == versionFile.commitish

			expect(newVersionFile?.iOS).toNot(beNil())
            guard let newCachedFramework = newVersionFile?.iOS else {
                fail("Expected newCachedFramework to not be nil")
                return
            }
			expect(newCachedFramework.count) == 1
			expect(newCachedFramework[0].name) == framework.name
			expect(newCachedFramework[0].hash) == framework.hash
			expect(newCachedFramework[0].swiftToolchainVersion) == framework.swiftToolchainVersion
		}

		it("should encode and decode correctly") {
			let jsonDictionary: [String: Any] = [
				"commitish": "v1.0",
				"iOS": [
					[
						"name": "TestFramework",
						"hash": "TestHASH",
						"swiftToolchainVersion": "4.2 (swiftlang-1000.11.37.1 clang-1000.11.45.1)",
					],
				],
			]
            guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonDictionary) else {
                fail("Could not load json data from dictionary")
                return
            }

            guard let versionFile = try? JSONDecoder().decode(VersionFile.self, from: jsonData) else {
                fail("Expected version file to not be nil")
                return
            }
			expect(versionFile.commitish) == "v1.0"

			// Check multiple frameworks
			let iOSCache = versionFile.iOS
			expect(iOSCache).notTo(beNil())
			expect(iOSCache?.count) == 1
			expect(iOSCache?[0].name) == "TestFramework"
			expect(iOSCache?[0].hash) == "TestHASH"
			expect(iOSCache?[0].swiftToolchainVersion) == "4.2 (swiftlang-1000.11.37.1 clang-1000.11.45.1)"

            guard let newJSONDictionary = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(versionFile))) as? [String: Any] else {
                fail("Expected json dictionary to not be nil")
                return
            }

			expect((newJSONDictionary["commitish"] as? String)) == "v1.0"
            guard let iosFramework = (newJSONDictionary["iOS"] as? [Any])?.first as? [String: String] else {
                fail("Expected ios framework to be present")
                return
            }
			expect(iosFramework["name"]) == "TestFramework"
			expect(iosFramework["hash"]) == "TestHASH"
			expect(iosFramework["swiftToolchainVersion"]) == "4.2 (swiftlang-1000.11.37.1 clang-1000.11.45.1)"
		}

		func validate(file: VersionFile, matches: Bool, platform: Platform, commitish: String, hashes: [String?],
		              swiftVersionMatches: [Bool], fileName: FileString = #file, line: UInt = #line) {
			_ = file.satisfies(platform: platform, commitish: commitish, hashes: hashes, swiftVersionMatches: swiftVersionMatches)
				.on(value: { didMatch in
					expect(didMatch, file: fileName, line: line) == matches
				})
				.wait()
		}

		it("should do proper validation checks") {
            guard let versionFileURL = Bundle(for: type(of: self)).url(forResource: "TestVersionFile", withExtension: "") else {
                fail("Expected TestVersionFile resource to exist")
                return
            }
            guard let versionFile = VersionFile(url: versionFileURL) else {
                fail("Expected version file to not be nil")
                return
            }

			// Everything matches
			validate(
				file: versionFile, matches: true, platform: .iOS,
				commitish: "v1.0", hashes: ["ios-framework1-hash", "ios-framework2-hash"], swiftVersionMatches: [true, true]
			)

			// One framework missing
			validate(
				file: versionFile, matches: false, platform: .iOS,
				commitish: "v1.0", hashes: ["ios-framework1-hash", nil], swiftVersionMatches: [true, true]
			)

			// One Swift version mismatch
			validate(
				file: versionFile, matches: false, platform: .iOS,
				commitish: "v1.0", hashes: ["ios-framework1-hash", "ios-framework2-hash"], swiftVersionMatches: [true, false]
			)

			// Mismatched commitish
			validate(
				file: versionFile, matches: false, platform: .iOS,
				commitish: "v1.1", hashes: ["ios-framework1-hash", "ios-framework2-hash"], swiftVersionMatches: [true, true]
			)

			// Version file has empty array for platform
			validate(
				file: versionFile, matches: true, platform: .tvOS,
				commitish: "v1.0", hashes: [nil, nil], swiftVersionMatches: [true, true]
			)

			// Version file has no entry for platform, should match
			validate(
				file: versionFile, matches: false, platform: .watchOS,
				commitish: "v1.0", hashes: [nil, nil], swiftVersionMatches: [true, true]
			)
		}
	}
}
