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
			expect(versionFile.xcodeVersion).to(equal("Xcode 8.2.1\nBuild version 8C1002"))

			// Check multiple frameworks
			let iOSCache = versionFile.iOS
			expect(iOSCache).notTo(beNil())
			expect(iOSCache!.count).to(equal(2))
			expect(iOSCache![0].name).to(equal("TestFramework1"))
			expect(iOSCache![0].md5).to(equal("ios-framework1-md5"))
			expect(iOSCache![1].name).to(equal("TestFramework2"))
			expect(iOSCache![1].md5).to(equal("ios-framework2-md5"))

			// Check different number of frameworks for a platform
			let macOSCache = versionFile.macOS
			expect(macOSCache).notTo(beNil())
			expect(macOSCache!.count).to(equal(1))
			expect(macOSCache![0].name).to(equal("TestFramework1"))
			expect(macOSCache![0].md5).to(equal("mac-framework1-md5"))

			// Check empty framework list
			let tvOSCache = versionFile.tvOS
			expect(tvOSCache).notTo(beNil())
			expect(tvOSCache!.count).to(equal(0))

			// Check missing platform
			let watchOSCache = versionFile.watchOS
			expect(watchOSCache).to(beNil())
		}

		it("should write and read back a version file correctly") {
			let framework = CachedFramework(name: "TestFramework", md5: "TestMD5")
			let versionFile = VersionFile(commitish: "v1.0", xcodeVersion: "Xcode 8.2.1\nBuild version 8C1002", macOS: nil, iOS: [framework], watchOS: nil, tvOS: nil)

			let versionFileURL = Bundle(for: type(of: self)).resourceURL!.appendingPathComponent("TestWriteVersionFile")

			let result = versionFile.write(to: versionFileURL)

			expect(result.error).to(beNil())

			expect(FileManager.default.fileExists(atPath: versionFileURL.path)).to(beTrue())

			let newVersionFile = VersionFile(url: versionFileURL)
			expect(newVersionFile).notTo(beNil())

			expect(newVersionFile!.commitish).to(equal(versionFile.commitish))
			expect(newVersionFile!.xcodeVersion).to(equal(versionFile.xcodeVersion))

			expect(newVersionFile!.iOS).toNot(beNil())
			let newCachedFramework = newVersionFile!.iOS!
			expect(newCachedFramework.count).to(equal(1))
			expect(newCachedFramework[0].name).to(equal(framework.name))
			expect(newCachedFramework[0].md5).to(equal(framework.md5))
		}

		it("should encode and decode correctly") {

			let jsonDictionary: [String: Any] = [
				"xcodeVersion": "Xcode 8.2.1\nBuild version 8C1002",
				"commitish": "v1.0",
				"iOS": [
					[
						"name": "TestFramework",
						"md5": "TestMD5"
					]
				]
			]

			let file: VersionFile? = Argo.decode(jsonDictionary)
			expect(file).notTo(beNil())

			let versionFile = file!
			expect(versionFile.commitish).to(equal("v1.0"))
			expect(versionFile.xcodeVersion).to(equal("Xcode 8.2.1\nBuild version 8C1002"))

			// Check multiple frameworks
			let iOSCache = versionFile.iOS
			expect(iOSCache).notTo(beNil())
			expect(iOSCache!.count).to(equal(1))
			expect(iOSCache![0].name).to(equal("TestFramework"))
			expect(iOSCache![0].md5).to(equal("TestMD5"))

			let value = versionFile.toJSONObject() as? [String: Any]
			expect(value).notTo(beNil())
			let newJSONDictionary = value!

			expect((newJSONDictionary["xcodeVersion"] as! String)).to(equal("Xcode 8.2.1\nBuild version 8C1002"))
			expect((newJSONDictionary["commitish"] as! String)).to(equal("v1.0"))
			let iosFramework = (newJSONDictionary["iOS"] as! [Any])[0] as! [String: String]
			expect(iosFramework["name"]).to(equal("TestFramework"))
			expect(iosFramework["md5"]).to(equal("TestMD5"))
		}

		func validate(file: VersionFile, matches: Bool, platform: Platform, commitish: String, xcodeVersion: String, md5s: SignalProducer<String?, CarthageError>, fileName: FileString = #file, line: UInt = #line) {
			_ = file.satisfies(platform: platform, commitish: commitish, xcodeVersion: xcodeVersion, md5s: md5s)
				.on(value: { didMatch in
					expect(didMatch, file: fileName, line: line).to(equal(matches))
				})
				.wait()
		}

		it("should do proper validation checks") {
			let versionFileURL = Bundle(for: type(of: self)).url(forResource: "TestVersionFile", withExtension: "")!
			let versionFile = VersionFile(url: versionFileURL)!

			// Everything matches
			validate(file: versionFile, matches: true, platform: .iOS, commitish: "v1.0", xcodeVersion: "Xcode 8.2.1\nBuild version 8C1002", md5s: SignalProducer(["ios-framework1-md5", "ios-framework2-md5"]))

			// One framework missing
			validate(file: versionFile, matches: false, platform: .iOS, commitish: "v1.0", xcodeVersion: "Xcode 8.2.1\nBuild version 8C1002", md5s: SignalProducer(["ios-framework1-md5", nil]))

			// Mismatched commitish
			validate(file: versionFile, matches: false, platform: .iOS, commitish: "v1.1", xcodeVersion: "Xcode 8.2.1\nBuild version 8C1002", md5s: SignalProducer(["ios-framework1-md5", "ios-framework2-md5"]))

			// Mismatched xcode version
			validate(file: versionFile, matches: false, platform: .iOS, commitish: "v1.0", xcodeVersion: "Xcode 8.3\nBuild version 8C3000", md5s: SignalProducer(["ios-framework1-md5", "ios-framework2-md5"]))

			// Version file has empty array for platform
			validate(file: versionFile, matches: true, platform: .tvOS, commitish: "v1.0", xcodeVersion: "Xcode 8.2.1\nBuild version 8C1002", md5s: SignalProducer([nil, nil]))

			// Version file has no entry for platform, should match
			validate(file: versionFile, matches: false, platform: .watchOS, commitish: "v1.0", xcodeVersion: "Xcode 8.2.1\nBuild version 8C1002", md5s: SignalProducer([nil, nil]))
		}
	}
}
