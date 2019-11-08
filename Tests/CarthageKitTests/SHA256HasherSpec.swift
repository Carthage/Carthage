@testable import CarthageKit
import Foundation
import Result
import Nimble
import Quick

class SHA256HasherSpec: QuickSpec {
	override func spec() {

		describe("hasher") {
			context("when hashing") {
				it("produces a valid hash") {

					guard let directoryURL = Bundle(for: type(of: self)).url(forResource: "Alamofire.framework", withExtension: nil),
						let executableURL = Bundle(url: directoryURL)!.executableURL else {
						fail("Cannot setup test case")
						return
					}

					let hasher = SHA256Hasher()
					try? hasher.hash(Data(contentsOf: executableURL))

					guard let sum: String =  try? hasher.finalize() else {
						fail("Hasher coult not finalize")
						return
					}
					// compare against known value generate by `shasum -a 256 <executableURL>`
					expect(sum) == "9c8be1a3001efaf6c31257bb36137fd92978bdf098fa3e1c30b925a55c57b516"
				}

				it("cannot be finalized twice") {
					let hasher = SHA256Hasher()
					expect {
						_ = try hasher.finalize()
						return try hasher.finalize()
					}
					.to(throwError(SHA256Hasher.HasherError.finalized))
				}
			}
		}
	}
}
