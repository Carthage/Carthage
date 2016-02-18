import Quick
import Nimble
import CarthageKit

class BuildArgumentsSpec: QuickSpec {
	override func spec() {
		describe("arguments") {
			context("when created with a workspace file") {
				let workspace = ProjectLocator.Workspace(NSURL(string: "file:///Foo/Bar/workspace.xcworkspace")!)

				it("has a default set of arguments specifying the workspace") {
					let subject = BuildArguments(project: workspace)

					expect(subject.arguments) == [
						"xcodebuild",
						"-workspace",
						"/Foo/Bar/workspace.xcworkspace",
						"CODE_SIGNING_REQUIRED=NO",
						"CODE_SIGN_IDENTITY="
					]
				}

				it("includes the scheme if one is given") {
					var subject = BuildArguments(project: workspace)
					subject.scheme = "exampleScheme"

					expect(subject.arguments) == [
						"xcodebuild",
						"-workspace",
						"/Foo/Bar/workspace.xcworkspace",
						"-scheme",
						"exampleScheme",
						"CODE_SIGNING_REQUIRED=NO",
						"CODE_SIGN_IDENTITY="
					]
				}

				it("includes the configuration if one is given") {
					var subject = BuildArguments(project: workspace)
					subject.configuration = "exampleConfiguration"

					expect(subject.arguments) == [
						"xcodebuild",
						"-workspace",
						"/Foo/Bar/workspace.xcworkspace",
						"-configuration",
						"exampleConfiguration",
						"CODE_SIGNING_REQUIRED=NO",
						"CODE_SIGN_IDENTITY="
					]
				}

				describe("specifying the sdk") {
					it("includes the sdk if it's not .MacOSX") {
						for sdk: SDK in [.iPhoneOS, .iPhoneSimulator, .watchOS, .watchSimulator, .tvOS, .tvSimulator] {
							var subject = BuildArguments(project: workspace)
							subject.sdk = sdk

							expect(subject.arguments) == [
								"xcodebuild",
								"-workspace",
								"/Foo/Bar/workspace.xcworkspace",
								"-sdk",
								sdk.rawValue,
								"CODE_SIGNING_REQUIRED=NO",
								"CODE_SIGN_IDENTITY="
							]
						}
					}

					it("does not include the sdk flag if .MacOSX is specified") {
						var subject = BuildArguments(project: workspace)
						subject.sdk = .MacOSX

						// Passing in -sdk macosx appears to break implicit dependency
						// resolution (see Carthage/Carthage#347).
						//
						// Since we wouldn't be trying to build this target unless it were
						// for OS X already, just let xcodebuild figure out the SDK on its
						// own.
						expect(subject.arguments) == [
							"xcodebuild",
							"-workspace",
							"/Foo/Bar/workspace.xcworkspace",
							"CODE_SIGNING_REQUIRED=NO",
							"CODE_SIGN_IDENTITY="
						]
					}
				}

				it("includes the destination if given") {
					var subject = BuildArguments(project: workspace)
					subject.destination = "exampleDestination"

					expect(subject.arguments) == [
						"xcodebuild",
						"-workspace",
						"/Foo/Bar/workspace.xcworkspace",
						"-destination",
						"exampleDestination",
						"CODE_SIGNING_REQUIRED=NO",
						"CODE_SIGN_IDENTITY="
					]
				}

				describe("specifying onlyActiveArchitecture") {
					it("includes ONLY_ACTIVE_ARCH=YES if it's set to true") {
						var subject = BuildArguments(project: workspace)
						subject.onlyActiveArchitecture = true

						expect(subject.arguments) == [
							"xcodebuild",
							"-workspace",
							"/Foo/Bar/workspace.xcworkspace",
							"ONLY_ACTIVE_ARCH=YES",
							"CODE_SIGNING_REQUIRED=NO",
							"CODE_SIGN_IDENTITY="
						]
					}

					it("includes ONLY_ACTIVE_ARCH=NO if it's set to false") {
						var subject = BuildArguments(project: workspace)
						subject.onlyActiveArchitecture = false

						expect(subject.arguments) == [
							"xcodebuild",
							"-workspace",
							"/Foo/Bar/workspace.xcworkspace",
							"ONLY_ACTIVE_ARCH=NO",
							"CODE_SIGNING_REQUIRED=NO",
							"CODE_SIGN_IDENTITY="
						]
					}
				}

				describe("specifying the bitcode generation mode") {
					it("includes BITCODE_GENERATION_MODE=marker if .Marker is set") {
						var subject = BuildArguments(project: workspace)
						subject.bitcodeGenerationMode = .Marker

						expect(subject.arguments) == [
							"xcodebuild",
							"-workspace",
							"/Foo/Bar/workspace.xcworkspace",
							"BITCODE_GENERATION_MODE=marker",
							"CODE_SIGNING_REQUIRED=NO",
							"CODE_SIGN_IDENTITY="
						]
					}

					it("includes BITCODE_GENERATION_MODE=bitcode if .Bitcode is set") {
						var subject = BuildArguments(project: workspace)
						subject.bitcodeGenerationMode = .Bitcode

						expect(subject.arguments) == [
							"xcodebuild",
							"-workspace",
							"/Foo/Bar/workspace.xcworkspace",
							"BITCODE_GENERATION_MODE=bitcode",
							"CODE_SIGNING_REQUIRED=NO",
							"CODE_SIGN_IDENTITY="
						]
					}
				}
			}

			context("when created with a project file") {
				let project = ProjectLocator.ProjectFile(NSURL(string: "file:///Foo/Bar/project.xcodeproj")!)

				it("has a default set of arguments specifying the project file") {
					let subject = BuildArguments(project: project)

					expect(subject.arguments) == [
						"xcodebuild",
						"-project",
						"/Foo/Bar/project.xcodeproj",
						"CODE_SIGNING_REQUIRED=NO",
						"CODE_SIGN_IDENTITY="
					]
				}

				it("includes the scheme if one is given") {
					var subject = BuildArguments(project: project)
					subject.scheme = "exampleScheme"

					expect(subject.arguments) == [
						"xcodebuild",
						"-project",
						"/Foo/Bar/project.xcodeproj",
						"-scheme",
						"exampleScheme",
						"CODE_SIGNING_REQUIRED=NO",
						"CODE_SIGN_IDENTITY="
					]
				}

				it("includes the configuration if one is given") {
					var subject = BuildArguments(project: project)
					subject.configuration = "exampleConfiguration"

					expect(subject.arguments) == [
						"xcodebuild",
						"-project",
						"/Foo/Bar/project.xcodeproj",
						"-configuration",
						"exampleConfiguration",
						"CODE_SIGNING_REQUIRED=NO",
						"CODE_SIGN_IDENTITY="
					]
				}

				describe("specifying the sdk") {
					it("includes the sdk if it's not .MacOSX") {
						for sdk: SDK in [.iPhoneOS, .iPhoneSimulator, .watchOS, .watchSimulator, .tvOS, .tvSimulator] {
							var subject = BuildArguments(project: project)
							subject.sdk = sdk

							expect(subject.arguments) == [
								"xcodebuild",
								"-project",
								"/Foo/Bar/project.xcodeproj",
								"-sdk",
								sdk.rawValue,
								"CODE_SIGNING_REQUIRED=NO",
								"CODE_SIGN_IDENTITY="
							]
						}
					}

					it("does not include the sdk flag if .MacOSX is specified") {
						var subject = BuildArguments(project: project)
						subject.sdk = .MacOSX

						// Passing in -sdk macosx appears to break implicit dependency
						// resolution (see Carthage/Carthage#347).
						//
						// Since we wouldn't be trying to build this target unless it were
						// for OS X already, just let xcodebuild figure out the SDK on its
						// own.
						expect(subject.arguments) == [
							"xcodebuild",
							"-project",
							"/Foo/Bar/project.xcodeproj",
							"CODE_SIGNING_REQUIRED=NO",
							"CODE_SIGN_IDENTITY="
						]
					}
				}

				it("includes the destination if given") {
					var subject = BuildArguments(project: project)
					subject.destination = "exampleDestination"

					expect(subject.arguments) == [
						"xcodebuild",
						"-project",
						"/Foo/Bar/project.xcodeproj",
						"-destination",
						"exampleDestination",
						"CODE_SIGNING_REQUIRED=NO",
						"CODE_SIGN_IDENTITY="
					]
				}

				describe("specifying onlyActiveArchitecture") {
					it("includes ONLY_ACTIVE_ARCH=YES if it's set to true") {
						var subject = BuildArguments(project: project)
						subject.onlyActiveArchitecture = true

						expect(subject.arguments) == [
							"xcodebuild",
							"-project",
							"/Foo/Bar/project.xcodeproj",
							"ONLY_ACTIVE_ARCH=YES",
							"CODE_SIGNING_REQUIRED=NO",
							"CODE_SIGN_IDENTITY="
						]
					}

					it("includes ONLY_ACTIVE_ARCH=NO if it's set to false") {
						var subject = BuildArguments(project: project)
						subject.onlyActiveArchitecture = false

						expect(subject.arguments) == [
							"xcodebuild",
							"-project",
							"/Foo/Bar/project.xcodeproj",
							"ONLY_ACTIVE_ARCH=NO",
							"CODE_SIGNING_REQUIRED=NO",
							"CODE_SIGN_IDENTITY="
						]
					}
				}

				describe("specifying the bitcode generation mode") {
					it("includes BITCODE_GENERATION_MODE=marker if .Marker is set") {
						var subject = BuildArguments(project: project)
						subject.bitcodeGenerationMode = .Marker

						expect(subject.arguments) == [
							"xcodebuild",
							"-project",
							"/Foo/Bar/project.xcodeproj",
							"BITCODE_GENERATION_MODE=marker",
							"CODE_SIGNING_REQUIRED=NO",
							"CODE_SIGN_IDENTITY="
						]
					}

					it("includes BITCODE_GENERATION_MODE=bitcode if .Bitcode is set") {
						var subject = BuildArguments(project: project)
						subject.bitcodeGenerationMode = .Bitcode

						expect(subject.arguments) == [
							"xcodebuild",
							"-project",
							"/Foo/Bar/project.xcodeproj",
							"BITCODE_GENERATION_MODE=bitcode",
							"CODE_SIGNING_REQUIRED=NO",
							"CODE_SIGN_IDENTITY="
						]
					}
				}
			}
		}
	}
}