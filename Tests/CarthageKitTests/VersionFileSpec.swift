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
			let versionFileURL = Bundle(for: type(of: self)).url(forResource: "TestVersionFile", withExtension: "")!
			let file = VersionFile(url: versionFileURL)
			expect(file).notTo(beNil())
			let versionFile = file!

			expect(versionFile.commitish) == "v1.0"

			// Check multiple frameworks
			let iOSCache = versionFile.iOS
			expect(iOSCache).notTo(beNil())
			expect(iOSCache!.count) == 2
			expect(iOSCache![0].name) == "TestFramework1"
			expect(iOSCache![0].hash) == "ios-framework1-hash"
			expect(iOSCache![0].linking) == .dynamic
			expect(iOSCache![0].swiftToolchainVersion) == "4.2 (swiftlang-1000.11.37.1 clang-1000.11.45.1)"
			expect(iOSCache![1].name) == "TestFramework2"
			expect(iOSCache![1].hash) == "ios-framework2-hash"
			expect(iOSCache![1].linking) == .static
			expect(iOSCache![1].swiftToolchainVersion) == "4.2.1 (swiftlang-1000.11.42 clang-1000.11.45.1)"

			// Check different number of frameworks for a platform
			let macOSCache = versionFile.macOS
			expect(macOSCache).notTo(beNil())
			expect(macOSCache!.count) == 1
			expect(macOSCache![0].name) == "TestFramework1"
			expect(macOSCache![0].hash) == "mac-framework1-hash"
			expect(macOSCache![0].linking).to(beNil())
			expect(macOSCache![0].swiftToolchainVersion) == "4.2 (swiftlang-1000.11.37.1 clang-1000.11.45.1)"

			// Check empty framework list
			let tvOSCache = versionFile.tvOS
			expect(tvOSCache).notTo(beNil())
			expect(tvOSCache!.count) == 0

			// Check missing platform
			let watchOSCache = versionFile.watchOS
			expect(watchOSCache).to(beNil())
		}

		it("should write and read back a version file correctly") {
			let framework = CachedFramework(name: "TestFramework",
							container: nil,
							libraryIdentifier: nil,
							hash: "TestHASH",
							linking: .dynamic,
							swiftToolchainVersion: "4.2 (swiftlang-1000.11.37.1 clang-1000.11.45.1)")
			let versionFile = VersionFile(commitish: "v1.0",
						      macOS: nil,
						      iOS: [framework],
						      watchOS: nil,
						      tvOS: nil)

			let versionFileURL = Bundle(for: type(of: self)).resourceURL!.appendingPathComponent("TestWriteVersionFile")

			let result = versionFile.write(to: versionFileURL)

			expect(result.error).to(beNil())

			expect(FileManager.default.fileExists(atPath: versionFileURL.path)).to(beTrue())

			let newVersionFile = VersionFile(url: versionFileURL)
			expect(newVersionFile).notTo(beNil())

			expect(newVersionFile!.commitish) == versionFile.commitish

			expect(newVersionFile!.iOS).toNot(beNil())
			let newCachedFramework = newVersionFile!.iOS!
			expect(newCachedFramework.count) == 1
			expect(newCachedFramework[0].name) == framework.name
			expect(newCachedFramework[0].hash) == framework.hash
			expect(newCachedFramework[0].linking) == .dynamic
			expect(newCachedFramework[0].swiftToolchainVersion) == framework.swiftToolchainVersion
			expect(newCachedFramework[0].isSwiftFramework) == framework.isSwiftFramework
		}

		it("should encode and decode correctly") {
			let jsonDictionary: [String: Any] = [
				"commitish": "v1.0",
				"iOS": [
					[
						"name": "TestFramework",
						"hash": "TestHASH",
						"linking": "dynamic",
						"swiftToolchainVersion": "4.2 (swiftlang-1000.11.37.1 clang-1000.11.45.1)",
					],
				],
			]
			let jsonData = try! JSONSerialization.data(withJSONObject: jsonDictionary)

			let file: VersionFile? = try? JSONDecoder().decode(VersionFile.self, from: jsonData)
			expect(file).notTo(beNil())

			let versionFile = file!
			expect(versionFile.commitish) == "v1.0"

			// Check multiple frameworks
			let iOSCache = versionFile.iOS
			expect(iOSCache).notTo(beNil())
			expect(iOSCache!.count) == 1
			expect(iOSCache![0].name) == "TestFramework"
			expect(iOSCache![0].hash) == "TestHASH"
			expect(iOSCache![0].linking) == .dynamic
			expect(iOSCache![0].swiftToolchainVersion) == "4.2 (swiftlang-1000.11.37.1 clang-1000.11.45.1)"
			expect(iOSCache![0].isSwiftFramework) == true

			let value = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(versionFile))) as? [String: Any]
			expect(value).notTo(beNil())
			let newJSONDictionary = value!

			expect((newJSONDictionary["commitish"] as! String)) == "v1.0" // swiftlint:disable:this force_cast
			let iosFramework = (newJSONDictionary["iOS"] as! [Any])[0] as! [String: String] // swiftlint:disable:this force_cast
			expect(iosFramework["name"]) == "TestFramework"
			expect(iosFramework["hash"]) == "TestHASH"
			expect(iosFramework["linking"]) == "dynamic"
			expect(iosFramework["swiftToolchainVersion"]) == "4.2 (swiftlang-1000.11.37.1 clang-1000.11.45.1)"
		}

		func validate(file: VersionFile, matches: Bool, platform: String, commitish: String, hashes: [String?],
		              swiftVersionMatches: [Bool], fileName: FileString = #file, line: UInt = #line) {
			_ = file.satisfies(platform: SDK(rawValue: platform)!, commitish: commitish, hashes: hashes, swiftVersionMatches: swiftVersionMatches)
				.on(value: { didMatch in
					expect(didMatch, file: fileName, line: line) == matches
				})
				.wait()
		}

		it("should do proper validation checks") {
			let versionFileURL = Bundle(for: type(of: self)).url(forResource: "TestVersionFile", withExtension: "")!
			let versionFile = VersionFile(url: versionFileURL)!

			// Everything matches
			validate(
				file: versionFile, matches: true, platform: "iphoneos",
				commitish: "v1.0", hashes: ["ios-framework1-hash", "ios-framework2-hash"], swiftVersionMatches: [true, true]
			)

			// One framework missing
			validate(
				file: versionFile, matches: false, platform: "iphoneos",
				commitish: "v1.0", hashes: ["ios-framework1-hash", nil], swiftVersionMatches: [true, true]
			)

			// One Swift version mismatch
			validate(
				file: versionFile, matches: false, platform: "iphoneos",
				commitish: "v1.0", hashes: ["ios-framework1-hash", "ios-framework2-hash"], swiftVersionMatches: [true, false]
			)

			// Mismatched commitish
			validate(
				file: versionFile, matches: false, platform: "iphoneos",
				commitish: "v1.1", hashes: ["ios-framework1-hash", "ios-framework2-hash"], swiftVersionMatches: [true, true]
			)

			// Version file has empty array for platform
			validate(
				file: versionFile, matches: true, platform: "tvos",
				commitish: "v1.0", hashes: [nil, nil], swiftVersionMatches: [true, true]
			)

			// Version file has no entry for platform, should match
			validate(
				file: versionFile, matches: false, platform: "watchOS",
				commitish: "v1.0", hashes: [nil, nil], swiftVersionMatches: [true, true]
			)
		}
		
		it("should do proper validation with objc framework") {
			let jsonDictionary: [String: Any] = [
				"commitish": "v1.0",
				"iOS": [
					[
						"name": "TestObjCFramework",
						"hash": "TestHASH",
						],
				],
				]
			let jsonData = try! JSONSerialization.data(withJSONObject: jsonDictionary)
			
			let versionFile: VersionFile! = try? JSONDecoder().decode(VersionFile.self, from: jsonData)
			validate(
				file: versionFile, matches: true, platform: "iphoneos",
				commitish: "v1.0", hashes: ["TestHASH"], swiftVersionMatches: [true]
			)
		}

		it("should compute the relative paths of static and dynamic frameworks") {
			let dynamicFramework = CachedFramework(
				name: "TestFramework",
				container: nil,
				libraryIdentifier: nil,
				hash: "TestHASH",
				linking: .dynamic,
				swiftToolchainVersion: "4.2 (swiftlang-1000.11.37.1 clang-1000.11.45.1)"
			)
			let staticFramework = CachedFramework(
				name: "TestFramework",
				container: nil,
				libraryIdentifier: nil,
				hash: "TestHASH",
				linking: .static,
				swiftToolchainVersion: "4.2 (swiftlang-1000.11.37.1 clang-1000.11.45.1)"
			)
			let xcframeworkFramework = CachedFramework(
				name: "TestFramework",
				container: "TestFramework.xcframework",
				libraryIdentifier: "ios-arm64_x86_64-simulator",
				hash: "TestHASH",
				linking: nil,
				swiftToolchainVersion: "5.3 (swiftlang-1200.0.29.2 clang-1200.0.30.1)"
			)
			let buildDirectory = URL(fileURLWithPath: "/TestBuild")

			expect(dynamicFramework.location(in: buildDirectory, sdk: .iOS).path) == "/TestBuild/iOS/TestFramework.framework"
			expect(staticFramework.location(in: buildDirectory, sdk: .iOS).path) == "/TestBuild/iOS/Static/TestFramework.framework"
			expect(xcframeworkFramework.location(in: buildDirectory, sdk: .iOS).path) ==
				"/TestBuild/TestFramework.xcframework/ios-arm64_x86_64-simulator/TestFramework.framework"
		}
	}
}
