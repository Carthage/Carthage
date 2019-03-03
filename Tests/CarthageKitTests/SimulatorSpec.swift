@testable import CarthageKit
import Foundation
import Nimble
import Quick

class SimulatorSpec: QuickSpec {
	private let decoder = JSONDecoder()
	
	override func spec() {
		func loadJSON(for resource: String) -> Data? {
			guard let url = Bundle(for: type(of: self)).url(forResource: resource, withExtension: "json") else {
				return nil
			}
			return try? Data(contentsOf: url)
		}
		
		describe("Simulator") {
			context("Xcode 10.0 or lower") {
				it("should be parsed") {
					let decoder = JSONDecoder()
					guard let data = loadJSON(for: "Simulators/availables") else {
						fail("Could not load json from Simulators/availables")
						return
					}
					let dictionary = try! decoder.decode([String: [String: [Simulator]]].self, from: data)
					let devices = dictionary["devices"]!
					
					let simulators = devices["iOS 12.0"]!
					expect(simulators.count).to(equal(2))
					let simulator = simulators.first!
					expect(simulator.udid).to(equal(UUID(uuidString: "A52BF797-F6F8-47F1-B559-68B66B553B23")!))
					expect(simulator.isAvailable).to(beTrue())
					expect(simulator.name).to(equal("iPhone 5s"))
					
					let unavailableSimulator = simulators.last!
					expect(unavailableSimulator.isAvailable).to(beFalse())
				}
			}
			
			context("Xcode 10.1 beta") {
				it("should be parsed") {
					let decoder = JSONDecoder()
					guard let data = loadJSON(for: "Simulators/availables-xcode101-beta") else {
						fail("Could not load json for Simulators/availables-xcode101-beta")
						return
					}
					let dictionary = try! decoder.decode([String: [String: [Simulator]]].self, from: data)
					let devices = dictionary["devices"]!
					
					let simulators = devices["iOS 12.0"]!
					expect(simulators.count).to(equal(2))
					let simulator = simulators.first!
					expect(simulator.udid).to(equal(UUID(uuidString: "A52BF797-F6F8-47F1-B559-68B66B553B23")!))
					expect(simulator.isAvailable).to(beTrue())
					expect(simulator.name).to(equal("iPhone 5s"))
					
					let unavailableSimulator = simulators.last!
					expect(unavailableSimulator.isAvailable).to(beFalse())
				}
			}
			
			context("Xcode 10.1") {
				it("should be parsed") {
					let decoder = JSONDecoder()
					guard let data = loadJSON(for: "Simulators/availables-xcode101") else {
						fail("Could not load json for Simulators/availables-xcode101-beta")
						return
					}
					let dictionary = try! decoder.decode([String: [String: [Simulator]]].self, from: data)
					let devices = dictionary["devices"]!
					
					let simulators = devices["iOS 12.0"]!
					expect(simulators.count).to(equal(2))
					let simulator = simulators.first!
					expect(simulator.udid).to(equal(UUID(uuidString: "A52BF797-F6F8-47F1-B559-68B66B553B23")!))
					expect(simulator.isAvailable).to(beTrue())
					expect(simulator.name).to(equal("iPhone 5s"))
					
					let unavailableSimulator = simulators.last!
					expect(unavailableSimulator.isAvailable).to(beFalse())
				}
			}
			
			context("Xcode 10.2 beta") {
				it("should be parsed") {
					let decoder = JSONDecoder()
					guard let data = loadJSON(for: "Simulators/availables-xcode102-beta") else {
						fail("Could not load json for Simulators/availables-xcode102-beta")
						return
					}
					let dictionary = try! decoder.decode([String: [String: [Simulator]]].self, from: data)
					let devices = dictionary["devices"]!
					
					let simulators = devices["com.apple.CoreSimulator.SimRuntime.iOS-12-0"]!
					expect(simulators.count).to(equal(2))
					let simulator = simulators.first!
					expect(simulator.udid).to(equal(UUID(uuidString: "A52BF797-F6F8-47F1-B559-68B66B553B23")!))
					expect(simulator.isAvailable).to(beTrue())
					expect(simulator.name).to(equal("iPhone 5s"))
					
					let unavailableSimulator = simulators.last!
					expect(unavailableSimulator.isAvailable).to(beFalse())
				}
			}
		}
		
		describe("selectAvailableSimulator(of:from:)") {
			context("when there are available simulators") {
				context("Xcode 10.0 or lower") {
					it("should return the first simulator of the latest version") {
						guard let data = loadJSON(for: "Simulators/availables") else {
							fail("Could not load json for Simulators/availables")
							return
						}
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
				
				context("Xcode 10.1 beta") {
					it("should return the first simulator of the latest version") {
						guard let data = loadJSON(for: "Simulators/availables-xcode101-beta") else {
							fail("Could not load json for Simulators/availables-xcode101-beta")
							return
						}
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
				
				context("Xcode 10.1") {
					it("should return the first simulator of the latest version") {
						guard let data = loadJSON(for: "Simulators/availables-xcode101") else {
							fail("Could not load json for Simulators/availables-xcode101")
							return
						}
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
				
				context("When the latest installed simulator is unavailable") {
					it("should return the first simulator of the latest version") {
						guard let data = loadJSON(for: "Simulators/availables-xcode102-with-unavailable-latest-simulators") else {
							fail("Could not load json for Simulators/availables-xcode102-with-unavailable-latest-simulators")
							return
						}
						let iPhoneSimulator = selectAvailableSimulator(of: .iPhoneSimulator, from: data)!
						expect(iPhoneSimulator.udid).to(equal(UUID(uuidString: "12972BD8-0153-452B-83F7-F253EA75C4FE")!))
						expect(iPhoneSimulator.isAvailable).to(beTrue())
						expect(iPhoneSimulator.name).to(equal("iPhone 5s"))
						
						let watchSimulator = selectAvailableSimulator(of: .watchSimulator, from: data)!
						expect(watchSimulator.udid).to(equal(UUID(uuidString: "3E3C4790-EB16-445B-9C39-2BD22C54B37A")!))
						expect(watchSimulator.isAvailable).to(beTrue())
						expect(watchSimulator.name).to(equal("Apple Watch Series 2 - 38mm"))
						
						let tvSimulator = selectAvailableSimulator(of: .tvSimulator, from: data)!
						expect(tvSimulator.udid).to(equal(UUID(uuidString: "4747A322-2660-4025-B1F7-90373369F808")!))
						expect(tvSimulator.isAvailable).to(beTrue())
						expect(tvSimulator.name).to(equal("Apple TV"))
					}
				}
				
				context("Xcode 10.2 beta") {
					it("should return the first simulator of the latest version") {
						guard let data = loadJSON(for: "Simulators/availables-xcode102-beta") else {
							fail("Could not load json for Simulators/availables-xcode102-beta")
							return
						}
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
			}
			
			context("when there is no available simulator") {
				it("should return nil") {
					guard let data = loadJSON(for: "Simulators/unavailable") else {
						fail("Could not load data for Simulators/unavailable")
						return
					}
					expect(selectAvailableSimulator(of: .watchSimulator, from: data)).to(beNil())
				}
			}
		}
		
		describe("parsePlatformVersion(for:from:)") {
			context("when the platform name is present") {
				it("should return the platform version") {
					let platformVersion = parsePlatformVersion(for: "iOS", from: "iOS 12.1")
					expect(platformVersion).to(equal("iOS 12.1"))
				}
				
				context("when the identifier has a prefix") {
					it("should return the platform version") {
						let platformVersion = parsePlatformVersion(for: "iOS", from: "com.apple.CoreSimulator.SimRuntime.iOS-12-1")
						expect(platformVersion).to(equal("iOS 12.1"))
					}
				}
			}
			
			context("when the platform name is missing") {
				it("should return nil") {
					let platformVersion = parsePlatformVersion(for: "iOS", from: "watchOS 5.2")
					expect(platformVersion).to(beNil())
				}
				
				context("when the identifier has a prefix") {
					it("should return nil") {
						let platformVersion = parsePlatformVersion(for: "iOS", from: "com.apple.CoreSimulator.SimRuntime.watchOS-5-2")
						expect(platformVersion).to(beNil())
					}
				}
			}
		}
	}
}
