@testable import CarthageKit
import Foundation
import Nimble
import Quick

private let singleJSON = """
{
"state": "Shutdown",
"availability": "(available)",
"name": "iPhone 5s",
"udid": "A52BF797-F6F8-47F1-B559-68B66B553B23"
}
"""

private let multipleJSON = """
{
"devices": {
"iOS 12.0": [
{
"state": "Shutdown",
"availability": "(available)",
"name": "iPhone 5s",
"udid": "A52BF797-F6F8-47F1-B559-68B66B553B23"
},
{
"state": "Booted",
"availability": "(available)",
"name": "iPhone 6",
"udid": "ABDA7BC1-DB72-4332-90C2-C3D9AA8A5003"
},
{
"state": "Creating",
"availability": "(unavailable, runtime profile not found)",
"name": "iPhone 6 Plus",
"udid": "12933F69-9DCA-4AAF-97D6-81F77E0F2665"
}
]
}
}
"""

class SimulatorSpec: QuickSpec {
	private let decoder = JSONDecoder()
	
	override func spec() {
		describe("Simulator") {
			it("Single device should be parsed") {
				let data = singleJSON.data(using: .utf8)!
				let simulator = try! self.decoder.decode(Simulator.self, from: data)
				expect(simulator.isAvailable).to(equal(true))
				expect(simulator.name).to(equal("iPhone 5s"))
				expect(simulator.udid).to(equal(UUID(uuidString: "A52BF797-F6F8-47F1-B559-68B66B553B23")))
			}
			
			it("Multiple devices should be parsed") {
				let data = multipleJSON.data(using: .utf8)!
				let devices = try! self.decoder.decode([String: [String: [Simulator]]].self, from: data)
				expect(devices["devices"]).notTo(beNil())
				expect(devices["devices"]!["iOS 12.0"]!.count).to(equal(3))
			}
		}
		
		describe("selectAvailableSimulator(of:from:)") {
			func loadJSON(for resource: String) -> Data {
				let url = Bundle(for: type(of: self)).url(forResource: resource, withExtension: "json")!
				return try! Data(contentsOf: url)
			}
			
			context("when there are available simulators") {
				it("should return the first simulator of the latest version") {
					let data = loadJSON(for: "Devices/availables")
					let iPhoneSimulator = selectAvailableSimulator(of: .iPhoneSimulator, from: data)!
					expect(iPhoneSimulator.udid).to(equal(UUID(uuidString: "A52BF797-F6F8-47F1-B559-68B66B553B23")!))
					expect(iPhoneSimulator.availability).to(equal(.available))
					expect(iPhoneSimulator.name).to(equal("iPhone 5s"))
					
					let watchSimulator = selectAvailableSimulator(of: .watchSimulator, from: data)!
					expect(watchSimulator.udid).to(equal(UUID(uuidString: "290C3D57-0FF0-407F-B33C-F1A55EA44019")!))
					expect(watchSimulator.availability).to(equal(.available))
					expect(watchSimulator.name).to(equal("Apple Watch - 38mm"))
					
					let tvSimulator = selectAvailableSimulator(of: .tvSimulator, from: data)
					expect(tvSimulator).to(beNil())
				}
			}
			
			context("when there is no available simulator") {
				it("should return nil") {
					let data = loadJSON(for: "Devices/unavailable")
					expect(selectAvailableSimulator(of: .watchSimulator, from: data)).to(beNil())
				}
			}
		}
	}
}
