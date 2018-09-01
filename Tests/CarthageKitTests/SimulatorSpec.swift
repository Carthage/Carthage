@testable import CarthageKit
import Foundation
import Nimble
import Quick

class SimulatorSpec: QuickSpec {
	private let decoder = JSONDecoder()
	
	override func spec() {
		func loadJSON(for resource: String) -> Data {
			let url = Bundle(for: type(of: self)).url(forResource: resource, withExtension: "json")!
			return try! Data(contentsOf: url)
		}

		describe("Simulator") {
			it("should be parsed") {
				let decoder = JSONDecoder()
				let data = loadJSON(for: "Simulators/availables")
				let dictionary = try! decoder.decode([String: [String: [Simulator]]].self, from: data)
				let devices = dictionary["devices"]!

				let simulators = devices["iOS 12.0"]!
				expect(simulators.count).to(equal(2))
				let simulator = simulators.first!
				expect(simulator.udid).to(equal(UUID(uuidString: "A52BF797-F6F8-47F1-B559-68B66B553B23")!))
				expect(simulator.isAvailable).to(beTrue())
				expect(simulator.name).to(equal("iPhone 5s"))
			}
		}
		
		describe("selectAvailableSimulator(of:from:)") {
			context("when there are available simulators") {
				it("should return the first simulator of the latest version") {
					let data = loadJSON(for: "Simulators/availables")
					let iPhoneSimulator = selectAvailableSimulator(of: .iPhoneSimulator, from: data)!
					expect(iPhoneSimulator.udid).to(equal(UUID(uuidString: "A52BF797-F6F8-47F1-B559-68B66B553B23")!))
					expect(iPhoneSimulator.isAvailable).to(beTrue())
					expect(iPhoneSimulator.name).to(equal("iPhone 5s"))
					
					let watchSimulator = selectAvailableSimulator(of: .watchSimulator, from: data)!
					expect(watchSimulator.udid).to(equal(UUID(uuidString: "290C3D57-0FF0-407F-B33C-F1A55EA44019")!))
					expect(watchSimulator.isAvailable).to(beTrue())
					expect(watchSimulator.name).to(equal("Apple Watch - 38mm"))
					
					let tvSimulator = selectAvailableSimulator(of: .tvSimulator, from: data)
					expect(tvSimulator).to(beNil())
				}
			}
			
			context("when there is no available simulator") {
				it("should return nil") {
					let data = loadJSON(for: "Simulators/unavailable")
					expect(selectAvailableSimulator(of: .watchSimulator, from: data)).to(beNil())
				}
			}
		}
	}
}
