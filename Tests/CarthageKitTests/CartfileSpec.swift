import CarthageKit
import Foundation
import Result
import Tentacle
import Nimble
import Quick

// swiftlint:disable:this force_try

class CartfileSpec: QuickSpec {
	override func spec() {
		it("should parse a Cartfile") {
			let testCartfileURL = Bundle(for: type(of: self)).url(forResource: "TestCartfile", withExtension: "")!
			let testCartfile = try! String(contentsOf: testCartfileURL, encoding: .utf8)

			let result = Cartfile.from(string: testCartfile)
			expect(result.error).to(beNil())

			let cartfile = result.value!

			let reactiveCocoa = Dependency.gitHub(.dotCom, Repository(owner: "ReactiveCocoa", name: "ReactiveCocoa"))
			let mantle = Dependency.gitHub(.dotCom, Repository(owner: "Mantle", name: "Mantle"))
			let libextobjc = Dependency.gitHub(.dotCom, Repository(owner: "jspahrsummers", name: "libextobjc"))
			let xcconfigs = Dependency.gitHub(.dotCom, Repository(owner: "jspahrsummers", name: "xcconfigs"))
			let iosCharts = Dependency.gitHub(.dotCom, Repository(owner: "danielgindi", name: "ios-charts"))
			let errorTranslations = Dependency.gitHub(
				.enterprise(url: URL(string: "https://enterprise.local/ghe")!), Repository(owner: "desktop", name: "git-error-translations")
			)
			let errorTranslations2 = Dependency.git(GitURL("https://enterprise.local/desktop/git-error-translations2.git"))
			let example1 = Dependency.gitHub(.dotCom, Repository(owner: "ExampleOrg", name: "ExamplePrj1"))
			let example2 = Dependency.gitHub(.dotCom, Repository(owner: "ExampleOrg", name: "ExamplePrj2"))
			let example3 = Dependency.gitHub(.dotCom, Repository(owner: "ExampleOrg", name: "ExamplePrj3"))
			let example4 = Dependency.gitHub(.dotCom, Repository(owner: "ExampleOrg", name: "ExamplePrj4"))
			
			expect(cartfile.dependencies) == [
				reactiveCocoa: .atLeast(SemanticVersion(major: 2, minor: 3, patch: 1)),
				mantle: .compatibleWith(SemanticVersion(major: 1, minor: 0, patch: 0)),
				libextobjc: .exactly(SemanticVersion(major: 0, minor: 4, patch: 1)),
				xcconfigs: .any,
				iosCharts: .any,
				errorTranslations: .any,
				errorTranslations2: .gitReference("development"),
				example1: .atLeast(SemanticVersion(major: 3, minor: 0, patch: 2, preRelease: "pre")),
				example2: .exactly(SemanticVersion(major: 3, minor: 0, patch: 2, preRelease: nil, buildMetadata: "build")),
				example3: .exactly(SemanticVersion(major: 3, minor: 0, patch: 2)),
				example4: .gitReference("release#2")
			]
		}

		it("should parse a Cartfile.resolved") {
			let testCartfileURL = Bundle(for: type(of: self)).url(forResource: "TestCartfile", withExtension: "resolved")!
			let testCartfile = try! String(contentsOf: testCartfileURL, encoding: .utf8)

			let result = ResolvedCartfile.from(string: testCartfile)
			expect(result.error).to(beNil())

			let resolvedCartfile = result.value!
			expect(resolvedCartfile.dependencies) == [
				.gitHub(.dotCom, Repository(owner: "ReactiveCocoa", name: "ReactiveCocoa")): PinnedVersion("v2.3.1"),
				.gitHub(.dotCom, Repository(owner: "Mantle", name: "Mantle")): PinnedVersion("40abed6e58b4864afac235c3bb2552e23bc9da47"),
			]
		}

		it("should detect duplicate dependencies in a single Cartfile") {
			let testCartfileURL = Bundle(for: type(of: self)).url(forResource: "DuplicateDependenciesCartfile", withExtension: "")!
			let testCartfile = try! String(contentsOf: testCartfileURL, encoding: .utf8)

			let result = Cartfile.from(string: testCartfile)
			expect(result.error).notTo(beNil())

			guard case let .duplicateDependencies(dupes)? = result.error else {
				fail("Cartfile should error with duplicate dependencies")
				return
			}

			let dependencies = dupes
				.map { $0.dependency }
				.sorted { $0.description < $1.description }
			expect(dupes.count) == 3

			let self2Dupe = dependencies[0]
			expect(self2Dupe) == Dependency.gitHub(.dotCom, Repository(owner: "self2", name: "self2"))

			let self3Dupe = dependencies[1]
			expect(self3Dupe) == Dependency.gitHub(.dotCom, Repository(owner: "self3", name: "self3"))
		}

		it("should detect duplicate dependencies across two Cartfiles") {
			let testCartfileURL = Bundle(for: type(of: self)).url(forResource: "DuplicateDependencies/Cartfile", withExtension: "")!
			let testCartfile2URL = Bundle(for: type(of: self)).url(forResource: "DuplicateDependencies/Cartfile.private", withExtension: "")!

			let testCartfile = try! String(contentsOf: testCartfileURL, encoding: .utf8)
			let testCartfile2 = try! String(contentsOf: testCartfile2URL, encoding: .utf8)

			let result = Cartfile.from(string: testCartfile)
			expect(result.error).to(beNil())

			let result2 = Cartfile.from(string: testCartfile2)
			expect(result2.error).to(beNil())

			let cartfile = result.value!
			expect(cartfile.dependencies.count) == 5

			let cartfile2 = result2.value!
			expect(cartfile2.dependencies.count) == 3

			let dupes = duplicateDependenciesIn(cartfile, cartfile2).sorted { $0.description < $1.description }
			expect(dupes.count) == 3

			let dupe1 = dupes[0]
			expect(dupe1) == Dependency.gitHub(.dotCom, Repository(owner: "1", name: "1"))

			let dupe3 = dupes[1]
			expect(dupe3) == Dependency.gitHub(.dotCom, Repository(owner: "3", name: "3"))

			let dupe5 = dupes[2]
			expect(dupe5) == Dependency.gitHub(.dotCom, Repository(owner: "5", name: "5"))
		}

		it("should not allow a binary framework with git reference") {
			let testCartfile = "binary \"https://server.com/myproject\" \"gitreference\""
			let result = Cartfile.from(string: testCartfile)

			expect(result.error) == .parseError(
				description: "binary dependencies cannot have a git reference for the version specifier in line: "
					+ "binary \"https://server.com/myproject\" \"gitreference\""
			)
		}
	}
}

class ResolvedCartfileSpec: QuickSpec {
	override func spec() {
		describe("description") {
			it("should output dependencies alphabetically") {
				let resolvedCartfile = ResolvedCartfile(dependencies: [
					.gitHub(.dotCom, Repository(owner: "antitypical", name: "Result")): PinnedVersion("3.0.0"),
					.gitHub(.dotCom, Repository(owner: "ReactiveCocoa", name: "ReactiveSwift")): PinnedVersion("v1.0.0"),
					.gitHub(.dotCom, Repository(owner: "ReactiveCocoa", name: "ReactiveCocoa")): PinnedVersion("v2.3.1"),
				])

				expect(resolvedCartfile.description) == "github \"ReactiveCocoa/ReactiveCocoa\" \"v2.3.1\"\ngithub \"ReactiveCocoa/ReactiveSwift\" "
					+ "\"v1.0.0\"\ngithub \"antitypical/Result\" \"3.0.0\"\n"
			}
		}
	}
}
