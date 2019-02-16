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
                    expect(URL(string: "file://github/com/binary.json")?.validateScheme()) == expected
                    expect(URL(string: "http://github.com")?.validateScheme(allowHTTP: true)) == expected
                    expect(URL(string: "https://github.com")?.validateScheme()) == expected
                    expect(URL(string: "https://github.com")?.validateScheme(allowHTTP: true)) == expected
                    expect(URL(string: "https://github.com")?.validateScheme(allowHTTP: false)) == expected
                }
                it("should be false") {
                    let expected = false
                    expect(URL(string: "invalid")?.validateScheme()) == expected
                    expect(URL(string: "invalid://github.com")?.validateScheme()) == expected
                    expect(URL(string: "http://github.com")?.validateScheme()) == expected
                    expect(URL(string: "http://github.com")?.validateScheme(allowHTTP: false)) == expected
                }
            }
        }
    }
}
