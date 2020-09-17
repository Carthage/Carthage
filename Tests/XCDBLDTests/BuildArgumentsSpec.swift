import Foundation
import Quick
import Nimble
import XCDBLD

class BuildArgumentsSpec: QuickSpec {
	override func spec() {

		func itCreatesBuildArguments(_ message: String, arguments: [String], compareTo: KeyPath<BuildArguments, [String]> = \.rawArguments, configure: @escaping (inout BuildArguments) -> Void) {
			let workspace = ProjectLocator.workspace(URL(string: "file:///Foo/Bar/workspace.xcworkspace")!)
			let project = ProjectLocator.projectFile(URL(string: "file:///Foo/Bar/project.xcodeproj")!)

			let codeSignArguments = [
				"CODE_SIGNING_REQUIRED=NO",
				"CODE_SIGN_IDENTITY=",
				"CARTHAGE=YES",
			]

			context("when configured with a workspace") {
				it(message) {
					var subject = BuildArguments(project: workspace)
					configure(&subject)

					expect(subject[keyPath: compareTo]) == [
						"xcodebuild",
						"-workspace",
						"/Foo/Bar/workspace.xcworkspace",
						] + arguments + codeSignArguments
				}
			}

			context("when configured with a project") {
				it(message) {
					var subject = BuildArguments(project: project)
					configure(&subject)

					expect(subject[keyPath: compareTo]) == [
						"xcodebuild",
						"-project",
						"/Foo/Bar/project.xcodeproj",
						] + arguments + codeSignArguments
				}
			}
		}

		describe("rawArguments") {
			func itCreatesBuildArguments(_ message: String, rawArguments: [String], configure: @escaping (inout BuildArguments) -> Void) {
				let workspace = ProjectLocator.workspace(URL(string: "file:///Foo/Bar/workspace.xcworkspace")!)
				let project = ProjectLocator.projectFile(URL(string: "file:///Foo/Bar/project.xcodeproj")!)

				let codeSignArguments = [
					"CODE_SIGNING_REQUIRED=NO",
					"CODE_SIGN_IDENTITY=",
					"CARTHAGE=YES",
				]

				context("when configured with a workspace") {
					it(message) {
						var subject = BuildArguments(project: workspace)
						configure(&subject)

						expect(subject.rawArguments) == [
							"xcodebuild",
							"-workspace",
							"/Foo/Bar/workspace.xcworkspace",
							] + rawArguments + codeSignArguments
					}
				}

				context("when configured with a project") {
					it(message) {
						var subject = BuildArguments(project: project)
						configure(&subject)

						expect(subject.rawArguments) == [
							"xcodebuild",
							"-project",
							"/Foo/Bar/project.xcodeproj",
							] + rawArguments + codeSignArguments
					}
				}
			}

			itCreatesBuildArguments("has a default set of arguments", rawArguments: []) { _ in }

			itCreatesBuildArguments("includes the scheme if one is given", rawArguments: ["-scheme", "exampleScheme"]) { subject in
				subject.scheme = Scheme("exampleScheme")
			}

			itCreatesBuildArguments("includes the configuration if one is given", rawArguments: ["-configuration", "exampleConfiguration"]) { subject in
				subject.configuration = "exampleConfiguration"
			}

			itCreatesBuildArguments("includes the derived data path", rawArguments: ["-derivedDataPath", "/path/to/derivedDataPath"]) { subject in
				subject.derivedDataPath = "/path/to/derivedDataPath"
			}

			itCreatesBuildArguments("includes empty derived data path", rawArguments: []) { subject in
				subject.derivedDataPath = ""
			}

			itCreatesBuildArguments("includes the the toolchain", rawArguments: ["-toolchain", "org.swift.3020160509a"]) { subject in
				subject.toolchain = "org.swift.3020160509a"
			}

			describe("specifying the sdk") {
				let macosx = SDK.knownIn2019YearSDKs.first(where: { $0.rawValue == "macosx" })!

				for sdk in SDK.knownIn2019YearSDKs.subtracting([macosx]) {
					itCreatesBuildArguments("includes \(sdk) in the argument if specified", arguments: ["-sdk", sdk.rawValue]) { subject in
						subject.sdk = sdk
					}
				}

				// Passing in -sdk macosx appears to break implicit dependency
				// resolution (see Carthage/Carthage#347).
				//
				// Since we wouldn't be trying to build this target unless it were
				// for macOS already, just let xcodebuild figure out the SDK on its
				// own.
				itCreatesBuildArguments("does not include the sdk flag if .macOSX is specified", arguments: []) { subject in
					subject.sdk = macosx
				}
			}

			itCreatesBuildArguments("includes the destination if given", arguments: ["-destination", "exampleDestination"]) { subject in
				subject.destination = "exampleDestination"
			}

			describe("specifying onlyActiveArchitecture") {
				itCreatesBuildArguments("includes ONLY_ACTIVE_ARCH=YES if it's set to true", arguments: ["ONLY_ACTIVE_ARCH=YES"]) { subject in
					subject.onlyActiveArchitecture = true
				}

				itCreatesBuildArguments("includes ONLY_ACTIVE_ARCH=NO if it's set to false", arguments: ["ONLY_ACTIVE_ARCH=NO"]) { subject in
					subject.onlyActiveArchitecture = false
				}
			}
		}
	}
}
