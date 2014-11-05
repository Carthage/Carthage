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
        beforeEach() {
            // unzip the repositories
            let testRepo = self.pathForFixtureRepositoryNamed("simple-repo")

            println(testRepo)
        }

        it("Should do some stuff") {

            expect(true == false).to(equal(false))
        }
    }
}

