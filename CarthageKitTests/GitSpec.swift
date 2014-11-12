//
//  GitSpec.swift
//  Carthage
//
//  Created by Alan Rogers on 3/11/2014.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import CarthageKit
import Quick
import Nimble

class GitSpec: CarthageSpec {
	override func spec() {
		var testRepoURL: NSURL!

		beforeEach {
			testRepoURL = self.pathForFixtureRepositoryNamed("simple-repo")
			let exists = NSFileManager.defaultManager().fileExistsAtPath(testRepoURL.path!)
			expect(exists).to(beTruthy())
		}
	}
}

