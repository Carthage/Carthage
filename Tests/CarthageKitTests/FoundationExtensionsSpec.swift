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
            let rootDirectory = URL(fileURLWithPath: "/tmp/CarthageKitTests-FoundationExtensionsSpec-FileManager_allDirectories")
            let directoryA = rootDirectory.appendingPathComponent("A", isDirectory: true)
            let directoryB = directoryA.appendingPathComponent("B", isDirectory: true)
            let directoryC = rootDirectory.appendingPathComponent("C", isDirectory: true)

            beforeEach {
                _ = try? FileManager.default.createDirectory(at: directoryB, withIntermediateDirectories: true, attributes: nil)
                _ = try? FileManager.default.createDirectory(at: directoryC, withIntermediateDirectories: true, attributes: nil)
                
                let data = Data(bytes: [0, 1, 2, 3])
                try! data.write(to: directoryA.appendingPathComponent("data.txt"))
            }
            
            afterEach {
                _ = try? FileManager.default.removeItem(at: rootDirectory)
            }
            
            it("should resolve the difference") {
                let expected: [URL] = [rootDirectory, directoryA, directoryB, directoryC]
                expect(FileManager.default.allDirectories(at: rootDirectory).map { $0.standardizedFileURL }).to(equal(expected))
            }
        }
    }
}
