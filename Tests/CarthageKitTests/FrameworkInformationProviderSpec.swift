@testable import CarthageKit
import Foundation
import Quick
import Nimble

final class FrameworkInformationProviderSpec: QuickSpec {
	override func spec() {
		describe("platformForFramework") {
			let testStaticFrameworkURL = Bundle(for: type(of: self)).url(forResource: "Alamofire.framework", withExtension: nil)!
			// Checks the framework's executable binary, not the Info.plist.
			// The Info.plist is missing from Alamofire's bundle on purpose.
			it("should check the framework's executable binary and produce a platform") {
				let sut = FrameworkInformationProvider()
				let actualPlatform = sut.platformForFramework(testStaticFrameworkURL).first()?.value
				expect(actualPlatform) == .iOS
			}
		}
	}
}
