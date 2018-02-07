import Foundation
import Nimble
import Quick

@testable import XCDBLD

class SDKSpec: QuickSpec {
	override func spec() {
		describe("\(SDK.self)") {
			describe("initializer") {
				it("should return nil for empty string") {
					expect(SDK(rawValue: "")).to(beNil())
				}
				
				it("should return nil for unexpected input") {
					expect(SDK(rawValue: "speakerOS")).to(beNil())
				}
				
				it("should return a valid value for expected input") {
					let watchOS = SDK(rawValue: "watchOS")
					expect(watchOS).notTo(beNil())
					expect(watchOS) == SDK.watchOS
					
					let watchOSSimulator = SDK(rawValue: "wAtchsiMulator")
					expect(watchOSSimulator).notTo(beNil())
					expect(watchOSSimulator) == SDK.watchSimulator
					
					let tvOS1 = SDK(rawValue: "tvOS")
					expect(tvOS1).notTo(beNil())
					expect(tvOS1) == SDK.tvOS
					
					let tvOS2 = SDK(rawValue: "appletvos")
					expect(tvOS2).notTo(beNil())
					expect(tvOS2) == SDK.tvOS
					
					let macos = SDK(rawValue: "macosx")
					expect(macos).notTo(beNil())
					expect(macos) == SDK.macOSX
					
					let ios = SDK(rawValue: "iphoneos")
					expect(ios).notTo(beNil())
					expect(ios) == SDK.iPhoneOS
				}
			}
		}
	}
}
