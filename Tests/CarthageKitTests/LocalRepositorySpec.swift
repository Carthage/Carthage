import Foundation
import Nimble
import Quick
import ReactiveSwift
import Result
import Tentacle
@testable import CarthageKit

class LocalRepositoryTest: QuickSpec {
	override func spec() {
		// Use this test case to write a local repo to some folder for testing with problematic dependencies without requiring a live connection to the underlying git repo.
		pending("should create a local mock repository from live repositories") {
			let projectUrl = URL(fileURLWithPath: "/tmp/Carthage")
			let repositoryUrl = URL(fileURLWithPath: "/tmp/Repository")
			do {
				
				if FileManager.default.fileExists(atPath: repositoryUrl.path) {
					try FileManager.default.removeItem(at: repositoryUrl)
				}
				
				let project: Project = Project(directoryURL: projectUrl)
				let repository = LocalRepository(directoryURL: repositoryUrl)
				try project.storeDependencies(to: repository, ignoreErrors: true).first()!.dematerialize()
			} catch(let error) {
				fail("Expected no error to occur: \(error)")
			}
		}
	}
}
