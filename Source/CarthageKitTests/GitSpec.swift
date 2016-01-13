//
//  GitSpec.swift
//  Carthage
//
//  Created by Syo Ikeda on 1/13/16.
//  Copyright © 2016 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import Nimble
import Quick

class GitSpec: QuickSpec {
	override func spec() {
		describe("GitURL") {
			describe("normalizedURLString") {
				it("should parse normal URL") {
					expect(GitURL("https://github.com/antitypical/Result.git")) == GitURL("https://user:password@github.com:443/antitypical/Result")
				}

				it("should parse local path") {
					expect(GitURL("/path/to/git/repo.git")) == GitURL("/path/to/git/repo")
				}

				it("should parse scp syntax") {
					expect(GitURL("git@github.com:antitypical/Result.git")) == GitURL("github.com:antitypical/Result")
				}
			}
		}
	}
}
