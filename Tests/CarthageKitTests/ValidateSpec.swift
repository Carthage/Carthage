@testable import CarthageKit
import Foundation
import Nimble
import Quick
import ReactiveSwift
import Result
import Tentacle
import Utility

import struct Foundation.URL

private extension CarthageError {
	var compatibilityInfos: [CompatibilityInfo] {
		if case let .invalidResolvedCartfile(infos) = self {
			return infos
		}
		return []
	}
}

class ValidateSpec: QuickSpec {
	override func spec() {
		let validCartfile = """
					github "Alamofire/Alamofire" "4.6.0"
					github "CocoaLumberjack/CocoaLumberjack" "3.4.1"
					github "Moya/Moya" "10.0.2"
					github "ReactiveCocoa/ReactiveSwift" "2.0.1"
					github "ReactiveX/RxSwift" "4.1.2"
					github "antitypical/Result" "3.2.4"
					github "yapstudios/YapDatabase" "3.0.2"
					"""

		let invalidCartfile = """
					github "Alamofire/Alamofire" "5.0.0"
					github "CocoaLumberjack/CocoaLumberjack" "commitish"
					github "Moya/Moya" "10.0.2"
					github "ReactiveCocoa/ReactiveSwift" "2.0.1"
					github "ReactiveX/RxSwift" "4.1.2"
					github "antitypical/Result" "4.0.0"
					github "yapstudios/YapDatabase" "3.0.2"
					"""

		let moyaDependency = Dependency.gitHub(.dotCom, Repository(owner: "Moya", name: "Moya"))
		let resultDependency = Dependency.gitHub(.dotCom, Repository(owner: "antitypical", name: "Result"))
		let alamofireDependency = Dependency.gitHub(.dotCom, Repository(owner: "Alamofire", name: "Alamofire"))
		let reactiveSwiftDependency = Dependency.gitHub(.dotCom, Repository(owner: "ReactiveCocoa", name: "ReactiveSwift"))
		let rxSwiftDependency = Dependency.gitHub(.dotCom, Repository(owner: "ReactiveX", name: "RxSwift"))
		let yapDatabaseDependency = Dependency.gitHub(.dotCom, Repository(owner: "yapstudios", name: "YapDatabase"))
		let cocoaLumberjackDependency = Dependency.gitHub(.dotCom, Repository(owner: "CocoaLumberjack", name: "CocoaLumberjack"))

		// These tuples represent the desired version of a dependency, paired with its parent dependency;
		// moya_3_1_0 indicates that Moya expects a version compatible with 3.1.0 of *another* dependency
		let moya_3_1_0 = (moyaDependency, VersionSpecifier.compatibleWith(Version(3, 1, 0)))
		let moya_4_1_0 = (moyaDependency, VersionSpecifier.compatibleWith(Version(4, 1, 0)))
		let reactiveSwift_3_2_1 = (reactiveSwiftDependency, VersionSpecifier.compatibleWith(Version(3, 2, 1)))

		describe("requirementsByDependency") {
			it("should group dependencies by parent dependency") {
				let resolvedCartfile = ResolvedCartfile.from(string: validCartfile)
				let project = Project(directoryURL: URL(string: "file:///var/empty/fake")!)

				let result = project.requirementsByDependency(resolvedCartfile: resolvedCartfile.value!, tryCheckoutDirectory: false).single()

				expect(result?.value?.count) == 3

				expect(Set(result?.value?[moyaDependency]?.map { $0.0 } ?? [])) ==
					   Set([resultDependency, alamofireDependency, reactiveSwiftDependency, rxSwiftDependency])

				expect(Set(result?.value?[reactiveSwiftDependency]?.map { $0.0 } ?? [])) == Set([resultDependency])

				expect(Set(result?.value?[yapDatabaseDependency]?.map { $0.0 } ?? [])) == Set([cocoaLumberjackDependency])
			}
		}

		describe("invert requirements") {
			it("should correctly invert a requirements dictionary") {
				let a = Dependency.gitHub(.dotCom, Repository(owner: "a", name: "a"))
				let b = Dependency.gitHub(.dotCom, Repository(owner: "b", name: "b"))
				let c = Dependency.gitHub(.dotCom, Repository(owner: "c", name: "c"))
				let d = Dependency.gitHub(.dotCom, Repository(owner: "d", name: "d"))
				let e = Dependency.gitHub(.dotCom, Repository(owner: "e", name: "e"))

				let v1 = VersionSpecifier.compatibleWith(Version(1, 0, 0))
				let v2 = VersionSpecifier.compatibleWith(Version(2, 0, 0))
				let v3 = VersionSpecifier.compatibleWith(Version(3, 0, 0))
				let v4 = VersionSpecifier.compatibleWith(Version(4, 0, 0))

				let requirements = [a: [b: v1, c: v2], d: [c: v3, e: v4]]
				let invertedRequirements = CompatibilityInfo.invert(requirements: requirements).value!
				for expected in [b: [a: v1], c: [a: v2, d: v3], e: [d: v4]] {
					expect(invertedRequirements.contains { $0.0 == expected.0 && $0.1 == expected.1 }) == true
				}
			}
		}

		describe("incompatibilities") {
			it("should identify incompatible dependencies") {
				let commitish = VersionSpecifier.gitReference("commitish")
				let v4_0_0 = VersionSpecifier.compatibleWith(Version(4, 0, 0))
				let v2_0_0 = VersionSpecifier.compatibleWith(Version(2, 0, 0))
				let v4_1_0 = VersionSpecifier.compatibleWith(Version(4, 1, 0))
				let v3_1_0 = VersionSpecifier.compatibleWith(Version(3, 1, 0))
				let v3_2_1 = VersionSpecifier.compatibleWith(Version(3, 2, 1))

				let dependencies = [rxSwiftDependency: PinnedVersion("4.1.2"),
									moyaDependency: PinnedVersion("10.0.2"),
									yapDatabaseDependency: PinnedVersion("3.0.2"),
									alamofireDependency: PinnedVersion("6.0.0"),
									reactiveSwiftDependency: PinnedVersion("2.0.1"),
									cocoaLumberjackDependency: PinnedVersion("commitish"),
									resultDependency: PinnedVersion("3.1.7")]

				let requirements = [moyaDependency: [rxSwiftDependency: v4_0_0,
													 reactiveSwiftDependency: v2_0_0,
													 alamofireDependency: v4_1_0,
													 resultDependency: v3_1_0],
									reactiveSwiftDependency: [resultDependency: v3_2_1],
									yapDatabaseDependency: [cocoaLumberjackDependency: commitish]]

				let infos = CompatibilityInfo.incompatibilities(for: dependencies, requirements: requirements)
					.value?
					.sorted { $0.dependency.name < $1.dependency.name }

				expect(infos?[0].dependency) == alamofireDependency
				expect(infos?[0].pinnedVersion) == PinnedVersion("6.0.0")

				expect(infos?[0].incompatibleRequirements.contains(where: { $0 == moya_4_1_0 })) == true

				expect(infos?[1].dependency) == resultDependency
				expect(infos?[1].pinnedVersion) == PinnedVersion("3.1.7")

				expect(infos?[1].incompatibleRequirements.contains(where: { $0 == reactiveSwift_3_2_1 })) == true
			}
		}

		describe("validate") {
			it("should identify a valid Cartfile.resolved as compatible") {
				let resolvedCartfile = ResolvedCartfile.from(string: validCartfile)
				let project = Project(directoryURL: URL(string: "file:///var/empty/fake")!)

				let result = project.validate(resolvedCartfile: resolvedCartfile.value!).single()

				expect(result?.value).notTo(beNil())
			}

			it("should identify incompatibilities in an invalid Cartfile.resolved") {
				let resolvedCartfile = ResolvedCartfile.from(string: invalidCartfile)
				let project = Project(directoryURL: URL(string: "file:///var/empty/fake")!)

				let error = project.validate(resolvedCartfile: resolvedCartfile.value!).single()?.error
				let infos = error?.compatibilityInfos.sorted { $0.dependency.name < $1.dependency.name }

				expect(infos?[0].dependency) == alamofireDependency
				expect(infos?[0].pinnedVersion) == PinnedVersion("5.0.0")

				expect(infos?[0].incompatibleRequirements.contains(where: { $0 == moya_4_1_0 })) == true

				expect(infos?[1].dependency) == resultDependency
				expect(infos?[1].pinnedVersion) == PinnedVersion("4.0.0")

				expect(infos?[1].incompatibleRequirements.contains(where: { $0 == moya_3_1_0 })) == true
				expect(infos?[1].incompatibleRequirements.contains(where: { $0 == reactiveSwift_3_2_1 })) == true

				expect(error?.description) ==
					"""
					The following incompatibilities were found in Cartfile.resolved:
					* Alamofire "5.0.0" is incompatible with Moya ~> 4.1.0
					* Result "4.0.0" is incompatible with Moya ~> 3.1.0
					* Result "4.0.0" is incompatible with ReactiveSwift ~> 3.2.1
					"""
			}
		}
	}
}
