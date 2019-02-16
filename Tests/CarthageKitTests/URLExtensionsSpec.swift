import Foundation
import Nimble
import Quick

@testable import CarthageKit

class URLExtensionsSpec: QuickSpec {
    override func spec() {
        describe("URL") {
            describe("schemeIsValid") {
                it("should be true") {
                    let expected = true
                    expect(URL(string: "https://github.com")?.schemeIsValid) == expected
                    expect(URL(string: "file://github/com/binary.json")?.schemeIsValid) == expected
                }
                it("should be false") {
                    let expected = false
                    expect(URL(string: "invalid")?.schemeIsValid) == expected
                    expect(URL(string: "invalid://github.com")?.schemeIsValid) == expected
                    expect(URL(string: "http://github.com")?.schemeIsValid) == expected
                }
            }
        }
    }
}
