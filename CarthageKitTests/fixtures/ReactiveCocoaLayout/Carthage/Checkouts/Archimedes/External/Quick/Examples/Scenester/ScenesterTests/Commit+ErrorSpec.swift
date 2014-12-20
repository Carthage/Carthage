//
//  Commit+ErrorSpec.swift
//  Scenester
//
//  Created by Brian Ivan Gesiak on 6/10/14.
//  Copyright (c) 2014 Brian Ivan Gesiak. All rights reserved.
//

import Scenester
import Quick
import Nimble

class Commit_ErrorSpec: QuickSpec {
    override func spec() {
        describe("commitError") {
            var code: CommitErrorCode!

            context("for a code of .NoCommits") {
                beforeEach { code = CommitErrorCode.NoCommits }
                it("returns an error") {
                    let error = Commit.commitError(code)
                    expect(error.localizedDescription).to(equal("The repo does not have any commits."))
                }
            }

            context("for a code of .InvalidCommit") {
                beforeEach { code = CommitErrorCode.InvalidCommit }
                it("returns an error") {
                    let error = Commit.commitError(code)
                    expect(error.localizedDescription).to(equal("The commit JSON is invalid."))
                }
            }

            context("for a code of .InvalidResponse") {
                beforeEach { code = CommitErrorCode.InvalidResponse }
                it("returns an error") {
                    let error = Commit.commitError(code)
                    expect(error.localizedDescription).to(equal("The response JSON for that repo does not contain commit data."))
                }
            }
        }
    }
}
