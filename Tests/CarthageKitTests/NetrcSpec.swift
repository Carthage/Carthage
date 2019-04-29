@testable import CarthageKit
import Foundation
import Nimble
import Quick

class NetrcSpec: QuickSpec {
    override func spec() {
        describe("load(from:)") {
            it("should load machines for a given inline format") {
                let content = "machine example.com login anonymous password qwerty"
                
                let machines = try? Netrc.load(from: content)
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
                
                let machines = try? Netrc.load(from: content)
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
                
                let machines = try? Netrc.load(from: content)
                expect(machines?.count) == 1
                
                let machine = machines?.first
                expect(machine?.name) == "example.com"
                expect(machine?.login) == "anonymous"
                expect(machine?.password) == "qwerty"
            }
            
            it("should load multiple machines for a given inline format") {
                let content = "machine example.com login anonymous password qwerty machine example2.com login anonymous2 password qwerty2"
                
                let machines = try? Netrc.load(from: content)
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
                
                let machines = try? Netrc.load(from: content)
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
                expect { try Netrc.load(from: content) }.to( throwError() )
            }
            
            it("should throw error for an empty machine values") {
                let content = "machine"
                expect { try Netrc.load(from: content) }.to( throwError() )
            }
            
            it("should throw error when login parameter is missing") {
                let content = "machine example.com anonymous password qwerty"
                expect { try Netrc.load(from: content) }.to( throwError() )
            }
            
            it("should throw error when password parameter is missing") {
                let content = "machine example.com login anonymous"
                expect { try Netrc.load(from: content) }.to( throwError() )
            }
        }
    }
}
