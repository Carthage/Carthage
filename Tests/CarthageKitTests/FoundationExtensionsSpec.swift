import Foundation
import Quick
import Nimble
@testable import CarthageKit

final class FoundationExtensionsSpec: QuickSpec {
    override func spec() {
        describe("Collection.unique") {
            context("when already unique") {
                it("return untouched collection") {
                    let unique: [Int] = [1, 2, 3]
                    expect(unique.unique()).to(equal(unique))
                    
                    let empty: [Int] = []
                    expect(empty.unique()).to(equal(empty))
                }
            }
            
            context("when has duplicates") {
                it("should return uniqued collection") {
                    let duplicates: [Int] = [1, 3, 1, 2, 3, 3, 1]
                    expect(duplicates.unique()).to(equal([1, 3, 2]))
                }
            }
        }
        
        describe("FileManager.allDirectories") {
            let sandboxURL = URL(fileURLWithPath: "/tmp/CarthageKitTests-FoundationExtensionsSpec-FileManager_allDirectories")
            let manager: FileManager = .default
            
            beforeEach {
                _ = try? manager.createDirectory(at: sandboxURL, withIntermediateDirectories: true, attributes: nil)
            }
            
            afterEach {
                _ = try? manager.removeItem(at: sandboxURL)
            }
            
            context("default") {
                let rootURL = sandboxURL.appendingPathComponent("Project", isDirectory: true)
                let frameworksURL = rootURL.appendingPathComponent("Frameworks", isDirectory: true)
                let sdkURL = frameworksURL.appendingPathComponent("SDK", isDirectory: true)
                
                beforeEach {
                    _ = try? manager.createDirectory(at: sdkURL, withIntermediateDirectories: true, attributes: nil)
                }
                
                it("should return all directories including receiver") {
                    let expected: [URL] = [rootURL, frameworksURL, sdkURL]
                    expect(manager.allDirectories(at: rootURL)).to(equal(expected))
                }
            }
            
            context("when has hidden directories") {
                let rootURL = sandboxURL.appendingPathComponent("Project", isDirectory: true)
                let gitURL = rootURL.appendingPathComponent(".git", isDirectory: true)
                let frameworksURL = rootURL.appendingPathComponent("Frameworks", isDirectory: true)
                let sdkURL = frameworksURL.appendingPathComponent("SDK", isDirectory: true)
                let sdkResourcesURL = sdkURL.appendingPathComponent("Resources", isDirectory: true)
                
                beforeEach {
                    _ = try? manager.createDirectory(at: sdkResourcesURL, withIntermediateDirectories: true, attributes: nil)
                    _ = try? manager.createDirectory(at: gitURL, withIntermediateDirectories: true, attributes: nil)
                    
                    var values = URLResourceValues()
                    values.isHidden = true
                    
                    var sdkURL = sdkURL
                    try! sdkURL.setResourceValues(values)
                }
                
                it("should skip hidden directories with underlying content") {
                    let expected: [URL] = [rootURL, frameworksURL]
                    expect(manager.allDirectories(at: rootURL)).to(equal(expected))
                }
            }
            
            context("when has ignored extensions") {
                let rootURL = sandboxURL.appendingPathComponent("Project", isDirectory: true)
                let frameworksURL = rootURL.appendingPathComponent("Frameworks", isDirectory: true)
                
                let someFrameworkURL = frameworksURL.appendingPathComponent("A.framework", isDirectory: true)
                let someFrameworkResourcesURL = someFrameworkURL.appendingPathComponent("Resources", isDirectory: true)
                
                let someFakeFrameworkURL = frameworksURL.appendingPathComponent(".framework", isDirectory: true)
                let otherURL = frameworksURL.appendingPathComponent("Framework.etc", isDirectory: true)
                

                beforeEach {
                    _ = try? manager.createDirectory(at: someFrameworkResourcesURL, withIntermediateDirectories: true, attributes: nil)
                    _ = try? manager.createDirectory(at: someFakeFrameworkURL, withIntermediateDirectories: true, attributes: nil)
                    _ = try? manager.createDirectory(at: otherURL, withIntermediateDirectories: true, attributes: nil)
                }
                
                it("should skip matching directories with underlying content") {
                    let expected: [URL] = [rootURL, frameworksURL, otherURL]
                    expect(manager.allDirectories(at: rootURL, ignoringExtensions: ["framework"])).to(equal(expected))
                }
            }
            
            context("Packages") {
                let rootURL = sandboxURL.appendingPathComponent("Project", isDirectory: true)
                let someBundleURL = rootURL.appendingPathComponent("Some.bundle", isDirectory: true)
                let someBundleResourcesURL = someBundleURL.appendingPathComponent("Resources", isDirectory: true)

                beforeEach {
                    _ = try? manager.createDirectory(at: someBundleResourcesURL, withIntermediateDirectories: true, attributes: nil)
                }
                
                it("should evaluate packages descendants") {
                    let expected: [URL] = [rootURL, someBundleURL, someBundleResourcesURL]
                    expect(manager.allDirectories(at: rootURL)).to(equal(expected))
                }
            }
        }
    }
}
