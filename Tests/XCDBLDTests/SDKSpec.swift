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
					
					let tvOSSimulator = SDK(rawValue: "appletvsimulator")
					expect(tvOSSimulator).notTo(beNil())
					expect(tvOSSimulator) == SDK.tvSimulator
					
					let macOS = SDK(rawValue: "macosx")
					expect(macOS).notTo(beNil())
					expect(macOS) == SDK.macOSX
					
					let iOS = SDK(rawValue: "iphoneos")
					expect(iOS).notTo(beNil())
					expect(iOS) == SDK.iPhoneOS
					
					let iOSimulator = SDK(rawValue: "iphonesimulator")
					expect(iOSimulator).notTo(beNil())
					expect(iOSimulator) == SDK.iPhoneSimulator
				}
			}
		}
	}
}
