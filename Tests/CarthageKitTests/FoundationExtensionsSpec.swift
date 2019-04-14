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
    }
}
