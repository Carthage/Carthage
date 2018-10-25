import XCDBLD
import Foundation
import Nimble
import Quick

class ProjectLocatorSpec: QuickSpec {
	override func spec() {
		describe("\(ProjectLocator.self)") {
			describe("sorting") {
				it("should put workspaces before projects") {
					let workspace = ProjectLocator.workspace(URL(fileURLWithPath: "/Z.xcworkspace"))
					let project = ProjectLocator.projectFile(URL(fileURLWithPath: "/A.xcodeproj"))
					expect(workspace < project) == true
				}

				it("should fall back to lexicographical sorting") {
					let workspaceA = ProjectLocator.workspace(URL(fileURLWithPath: "/A.xcworkspace"))
					let workspaceB = ProjectLocator.workspace(URL(fileURLWithPath: "/B.xcworkspace"))
					expect(workspaceA < workspaceB) == true

					let projectA = ProjectLocator.projectFile(URL(fileURLWithPath: "/A.xcodeproj"))
					let projectB = ProjectLocator.projectFile(URL(fileURLWithPath: "/B.xcodeproj"))
					expect(projectA < projectB) == true
				}

				it("should put top-level directories first") {
					let top = ProjectLocator.projectFile(URL(fileURLWithPath: "/Z.xcodeproj"))
					let bottom = ProjectLocator.workspace(URL(fileURLWithPath: "/A/A.xcodeproj"))
					expect(top < bottom) == true
				}
			}
		}
	}
}
