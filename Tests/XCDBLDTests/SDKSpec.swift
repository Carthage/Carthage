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

class SD_KSpec: QuickSpec {
	override func spec() {
		describe("\(SD_K.self)") {
			describe("initializer") {
				it("should return nil for empty string") {
					expect(SD_K(rawValue: "")).to(beNil())
				}
				
				it("should return nil for unexpected input") {
					expect(SD_K(rawValue: "speakerOS")).to(beNil())
				}
				
				it("should return a valid value for expected input") {
					let watchOS = SD_K(rawValue: "watchOS")
					expect(watchOS).notTo(beNil())
					expect(watchOS) == SD_K.watchOS
					
					let watchOSSimulator = SD_K(rawValue: "wAtchsiMulator")
					expect(watchOSSimulator).notTo(beNil())
					expect(watchOSSimulator) == SD_K.watchSimulator
					
					let tvOS1 = SD_K(rawValue: "tvOS")
					expect(tvOS1).notTo(beNil())
					expect(tvOS1) == SD_K.tvOS
					
					let tvOS2 = SD_K(rawValue: "appletvos")
					expect(tvOS2).notTo(beNil())
					expect(tvOS2) == SD_K.tvOS
					
					let tvOSSimulator = SD_K(rawValue: "appletvsimulator")
					expect(tvOSSimulator).notTo(beNil())
					expect(tvOSSimulator) == SD_K.tvSimulator
					
					let macOS = SD_K(rawValue: "macosx")
					expect(macOS).notTo(beNil())
					expect(macOS) == SD_K.macOSX
					
					let iOS = SD_K(rawValue: "iphoneos")
					expect(iOS).notTo(beNil())
					expect(iOS) == SD_K.iPhoneOS
					
					let iOSimulator = SD_K(rawValue: "iphonesimulator")
					expect(iOSimulator).notTo(beNil())
					expect(iOSimulator) == SD_K.iPhoneSimulator
				}
			}
		}
	}
}
