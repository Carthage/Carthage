@testable import CarthageKit
import Foundation
import Nimble
import Quick

class NetrcSpec: QuickSpec {
    override func spec() {
        describe("load(from:)") {
            
            it("should load machines for a given inline format") {
                let content = "machine example.com login carthage password admin"
                
                let machines = try? Netrc.load(from: content)
                expect(machines?.count) == 1
                
                let machine = machines?.first
                expect(machine?.name) == "example.com"
                expect(machine?.login) == "carthage"
                expect(machine?.password) == "admin"
                expect(machine?.isDefault) == false
            }
            
            it("should load machines for a given multi-line format") {
                let content = """
                    machine example.com
                    login carthage
                    password admin
                    """
                
                let machines = try? Netrc.load(from: content)
                expect(machines?.count) == 1
                
                let machine = machines?.first
                expect(machine?.name) == "example.com"
                expect(machine?.login) == "carthage"
                expect(machine?.password) == "admin"
                expect(machine?.isDefault) == false
            }
            
            it("should load machines for a given multi-line + whitespaces format") {
                let content = """
                    machine  example.com login     carthage
                    password                  admin
                    """
                
                let machines = try? Netrc.load(from: content)
                expect(machines?.count) == 1
                
                let machine = machines?.first
                expect(machine?.name) == "example.com"
                expect(machine?.login) == "carthage"
                expect(machine?.password) == "admin"
                expect(machine?.isDefault) == false
            }
        }
    }
    
}

// 🦁 TODO: Implement test cases

// login carthage password admin
// machine login carthage password admin
// machine example.com login password admin
// machine example.com login carthage password admin machine example2.com login carthage2 password admin2
