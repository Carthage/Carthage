//
//  ExampleMetadataFunctionalTests.swift
//  Quick
//
//  Created by Brian Gesiak on 8/26/14.
//  Copyright (c) 2014 Brian Ivan Gesiak. All rights reserved.
//

import Quick
import Nimble

class ExampleMetadataFunctionalTestsSpec: QuickSpec {
    override func spec() {
        var currentExampleName = ""
        var lastExampleName = ""

        beforeEach { (exampleMetadata: ExampleMetadata) -> () in
            currentExampleName = exampleMetadata.example.name
        }

        afterEach { (exampleMetadata: ExampleMetadata) -> () in
            lastExampleName = exampleMetadata.example.name
        }

        it("calls beforeEach with the metadata for the first example") {
            expect(currentExampleName).to(contain("calls beforeEach with the metadata"))
        }

        it("calls afterEach with the metadata for the first example") {
            expect(lastExampleName).to(contain("calls beforeEach with the metadata"))
        }
    }
}
