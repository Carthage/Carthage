@testable import CarthageKit
import Foundation
import Nimble
import Quick

class NetrcSpec: QuickSpec {
	override func spec() {
		describe("loading") {
			it("should load machines for a given inline format") {
				let content = "machine example.com login anonymous password qwerty"
				
				let machines = Netrc.from(content).value?.machines
				expect(machines?.count) == 1
				
				let machine = machines?.first
				expect(machine?.name) == "example.com"
				expect(machine?.login) == "anonymous"
				expect(machine?.password) == "qwerty"
			}
			
			it("should load machines for a given multi-line format") {
				let content = """
                    machine example.com
                    login anonymous
                    password qwerty
                    """
				
				let machines = Netrc.from(content).value?.machines
				expect(machines?.count) == 1
				
				let machine = machines?.first
				expect(machine?.name) == "example.com"
				expect(machine?.login) == "anonymous"
				expect(machine?.password) == "qwerty"
			}
			
			it("should load machines for a given multi-line format with comments") {
				let content = """
                    ## This is a comment
                    # This is another comment
                    machine example.com # This is an inline comment
                    login anonymous
                    password qwerty # and # another #one
                    """
				
				let machines = Netrc.from(content).value?.machines
				expect(machines?.count) == 1
				
				let machine = machines?.first
				expect(machine?.name) == "example.com"
				expect(machine?.login) == "anonymous"
				expect(machine?.password) == "qwerty"
			}
			
			it("should load machines for a given multi-line + whitespaces format") {
				let content = """
                    machine  example.com login     anonymous
                    password                  qwerty
                    """
				
				let machines = Netrc.from(content).value?.machines
				expect(machines?.count) == 1
				
				let machine = machines?.first
				expect(machine?.name) == "example.com"
				expect(machine?.login) == "anonymous"
				expect(machine?.password) == "qwerty"
			}
			
			it("should load multiple machines for a given inline format") {
				let content = "machine example.com login anonymous password qwerty machine example2.com login anonymous2 password qwerty2"
				
				let machines = Netrc.from(content).value?.machines
				expect(machines?.count) == 2
				
				var machine = machines?[0]
				expect(machine?.name) == "example.com"
				expect(machine?.login) == "anonymous"
				expect(machine?.password) == "qwerty"
				
				machine = machines?[1]
				expect(machine?.name) == "example2.com"
				expect(machine?.login) == "anonymous2"
				expect(machine?.password) == "qwerty2"
			}
			
			it("should load multiple machines for a given multi-line format") {
				let content = """
                    machine  example.com login     anonymous
                    password                  qwerty
                    machine example2.com
                    login anonymous2
                    password qwerty2
                    """
				
				let machines = Netrc.from(content).value?.machines
				expect(machines?.count) == 2
				
				var machine = machines?[0]
				expect(machine?.name) == "example.com"
				expect(machine?.login) == "anonymous"
				expect(machine?.password) == "qwerty"
				
				machine = machines?[1]
				expect(machine?.name) == "example2.com"
				expect(machine?.login) == "anonymous2"
				expect(machine?.password) == "qwerty2"
			}
			
			it("should throw error when machine parameter is missing") {
				let content = "login anonymous password qwerty"
				let error = Netrc.from(content).error
				
				switch error {
				case .some(.machineNotFound):
					break
				default:
					fail("Expected machineNotFound error")
				}
			}
			
			it("should throw error for an empty machine values") {
				let content = "machine"
				let error = Netrc.from(content).error
				
				switch error {
				case .some(.machineNotFound):
					break
				default:
					fail("Expected machineNotFound error")
				}
			}
			
			it("should throw error when login parameter is missing") {
				let content = "machine example.com anonymous password qwerty"
				let error = Netrc.from(content).error
				
				switch error {
				case .some(.missingValueForToken(let token)):
					expect(token) == "login"
				default:
					fail("Expected missingValueForToken error")
				}
			}
			
			it("should throw error when password parameter is missing") {
				let content = "machine example.com login anonymous"
				let error = Netrc.from(content).error
				
				switch error {
				case .some(.missingValueForToken(let password)):
					expect(password) == "password"
				default:
					fail("Expected missingValueForToken error")
				}
			}
			
			it("should return authorization when config contains a given machine") {
				let content = "machine example.com login anonymous password qwerty"
				
				let netrc = Netrc.from(content).value
				let result = netrc?.authorization(for: URL(string: "https://example.com")!)
				
				let data = "anonymous:qwerty".data(using: .utf8)!.base64EncodedString()
				expect(result) == "Basic \(data)"
			}
			
			it("should not return authorization when config does not contain a given machine") {
				let content = "machine example.com login anonymous password qwerty"
				
				let netrc = Netrc.from(content).value
				let result = netrc?.authorization(for: URL(string: "https://example99.com")!)
				
				expect(result).to(beNil())
			}
			
			
		}
	}
}
