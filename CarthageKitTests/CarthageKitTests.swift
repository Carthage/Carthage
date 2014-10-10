//
//  CarthageKitTests.swift
//  CarthageKitTests
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import XCTest
import CarthageKit

class CarthageKitTests: XCTestCase {
	func testScript() {
		switch script() {
		case let .Right(descriptor):
			println(descriptor.value)
		case let .Left(error):
			println(error.value)
		}
	}
}
