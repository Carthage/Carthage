//
//  VersionFileSpec.swift
//  Carthage
//
//  Created by Stephen Marquis on 2/3/17.
//  Copyright © 2017 Carthage. All rights reserved.
//

import Foundation
import Quick
import Nimble
import Argo
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

			expect(versionFile.commitish).to(equal("v1.0"))

			// Check multiple frameworks
			let iOSCache = versionFile.iOS
			expect(iOSCache).notTo(beNil())
			expect(iOSCache!.count).to(equal(2))
			expect(iOSCache![0].name).to(equal("TestFramework1"))
			expect(iOSCache![0].hash).to(equal("ios-framework1-hash"))
			expect(iOSCache![1].name).to(equal("TestFramework2"))
			expect(iOSCache![1].hash).to(equal("ios-framework2-hash"))

			// Check different number of frameworks for a platform
			let macOSCache = versionFile.macOS
			expect(macOSCache).notTo(beNil())
			expect(macOSCache!.count).to(equal(1))
			expect(macOSCache![0].name).to(equal("TestFramework1"))
			expect(macOSCache![0].hash).to(equal("mac-framework1-hash"))

			// Check empty framework list
			let tvOSCache = versionFile.tvOS
			expect(tvOSCache).notTo(beNil())
			expect(tvOSCache!.count).to(equal(0))

			// Check missing platform
			let watchOSCache = versionFile.watchOS
			expect(watchOSCache).to(beNil())
		}

		it("should write and read back a version file correctly") {
			let framework = CachedFramework(name: "TestFramework", hash: "TestHASH")
			let versionFile = VersionFile(commitish: "v1.0", macOS: nil, iOS: [framework], watchOS: nil, tvOS: nil)

			let versionFileURL = Bundle(for: type(of: self)).resourceURL!.appendingPathComponent("TestWriteVersionFile")

			let result = versionFile.write(to: versionFileURL)

			expect(result.error).to(beNil())

			expect(FileManager.default.fileExists(atPath: versionFileURL.path)).to(beTrue())

			let newVersionFile = VersionFile(url: versionFileURL)
			expect(newVersionFile).notTo(beNil())

			expect(newVersionFile!.commitish).to(equal(versionFile.commitish))

			expect(newVersionFile!.iOS).toNot(beNil())
			let newCachedFramework = newVersionFile!.iOS!
			expect(newCachedFramework.count).to(equal(1))
			expect(newCachedFramework[0].name).to(equal(framework.name))
			expect(newCachedFramework[0].hash).to(equal(framework.hash))
		}

		it("should encode and decode correctly") {

			let jsonDictionary: [String: Any] = [
				"commitish": "v1.0",
				"iOS": [
					[
						"name": "TestFramework",
						"hash": "TestHASH"
					]
				]
			]

			let file: VersionFile? = Argo.decode(jsonDictionary)
			expect(file).notTo(beNil())

			let versionFile = file!
			expect(versionFile.commitish).to(equal("v1.0"))

			// Check multiple frameworks
			let iOSCache = versionFile.iOS
			expect(iOSCache).notTo(beNil())
			expect(iOSCache!.count).to(equal(1))
			expect(iOSCache![0].name).to(equal("TestFramework"))
			expect(iOSCache![0].hash).to(equal("TestHASH"))

			let value = versionFile.toJSONObject() as? [String: Any]
			expect(value).notTo(beNil())
			let newJSONDictionary = value!

			expect((newJSONDictionary["commitish"] as! String)).to(equal("v1.0"))
			let iosFramework = (newJSONDictionary["iOS"] as! [Any])[0] as! [String: String]
			expect(iosFramework["name"]).to(equal("TestFramework"))
			expect(iosFramework["hash"]).to(equal("TestHASH"))
		}

		func validate(file: VersionFile, matches: Bool, platform: Platform, commitish: String, hashes: [String?], swiftVersionMatches: [Bool], fileName: FileString = #file, line: UInt = #line) {
			_ = file.satisfies(platform: platform, commitish: commitish, hashes: hashes, swiftVersionMatches: swiftVersionMatches)
				.on(value: { didMatch in
					expect(didMatch, file: fileName, line: line).to(equal(matches))
				})
				.wait()
		}

		it("should do proper validation checks") {
			let versionFileURL = Bundle(for: type(of: self)).url(forResource: "TestVersionFile", withExtension: "")!
			let versionFile = VersionFile(url: versionFileURL)!

			// Everything matches
			validate(file: versionFile, matches: true, platform: .iOS, commitish: "v1.0", hashes: ["ios-framework1-hash", "ios-framework2-hash"], swiftVersionMatches: [true, true])

			// One framework missing
			validate(file: versionFile, matches: false, platform: .iOS, commitish: "v1.0", hashes: ["ios-framework1-hash", nil], swiftVersionMatches: [true, true])

			// One Swift version mismatch
			validate(file: versionFile, matches: false, platform: .iOS, commitish: "v1.0", hashes: ["ios-framework1-hash", "ios-framework2-hash"], swiftVersionMatches: [true, false])

			// Mismatched commitish
			validate(file: versionFile, matches: false, platform: .iOS, commitish: "v1.1", hashes: ["ios-framework1-hash", "ios-framework2-hash"], swiftVersionMatches: [true, true])

			// Version file has empty array for platform
			validate(file: versionFile, matches: true, platform: .tvOS, commitish: "v1.0", hashes: [nil, nil], swiftVersionMatches: [true, true])

			// Version file has no entry for platform, should match
			validate(file: versionFile, matches: false, platform: .watchOS, commitish: "v1.0", hashes: [nil, nil], swiftVersionMatches: [true, true])
		}
	}
}
