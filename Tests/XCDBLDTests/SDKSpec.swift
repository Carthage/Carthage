import Foundation
import Nimble
import Quick

@testable import XCDBLD

class SDKEncompassingPlatformsSpec: QuickSpec {
	override func spec() {
		describe("platformSimulatorlessFromHeuristic") {
			it("should parse from different heuristics correctly") {
				let pairs: KeyValuePairs = [
					SDK(name: "platformboxsimulator", simulatorHeuristic: "Simulator - PlatformBox"): (true, "PlatformBox"),
					SDK(name: "PlatformBoxSimulator", simulatorHeuristic: ""): (true, "PlatformBox"),
					SDK(name: "platformboxsimulator", simulatorHeuristic: ""): (true, "platformbox"),
					SDK(name: "PlatformBox", simulatorHeuristic: ""): (false, "PlatformBox"),
					SDK(name: "platformbox", simulatorHeuristic: ""): (false, "platformbox"),
					SDK(name: "wAtchsiMulator", simulatorHeuristic: ""): (true, "watchOS"),
					SDK(name: "macosx", simulatorHeuristic: ""): (false, "Mac"), /* special case */
				]

				pairs.forEach { sdk, result in
					expect(sdk.isSimulator) == result.0
					expect(sdk.platformSimulatorlessFromHeuristic) == result.1
				}
			}
		}

		/*
		describe("BuildPlatform") {
			it("should parseSet and error where necessary") {
				expect {
					try BuildPlatform.parseSet(string: "ios,all")
				}.to(throwError())

				expect {
					try BuildPlatform.parseSet(string: "all")
				} == BuildPlatform.all

				expect {
					try BuildPlatform.parseSet(string: "all,all")
				} == BuildPlatform.all

				expect {
					try BuildPlatform.parseSet(string: "ios")
				}.notTo(throwError())
				
				expect {
					try BuildPlatform.parseSet(string: "all,ios")
				}.to(throwError())
		*/

		describe("Associated Sets of Known-In-2019-Year SDKs") {
			it("should map correctly") {
				expect(SDK.associatedSetOfKnownIn2019YearSDKs("TVOS").map { $0.rawValue }.sorted())
					== [ "appletvos", "appletvsimulator" ]
				expect(SDK.associatedSetOfKnownIn2019YearSDKs("ios").map { $0.rawValue }.sorted())
					== [ "iphoneos", "iphonesimulator" ]
			}
		}
	}
}
