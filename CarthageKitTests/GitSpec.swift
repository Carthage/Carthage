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

class GitSpec: QuickSpec {
    override func spec() {
        let archiveURL = NSBundle(forClass: self.dynamicType).URLForResource("repositories", withExtension: "zip", subdirectory: "fixtures")!

    }
}

