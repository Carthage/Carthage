//
//  TaskSpec.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import Nimble
import Quick
import ReactiveCocoa

class TaskSpec: QuickSpec {
	override func spec() {
		let standardOutput = SignalingProperty(NSData())
		let standardError = SignalingProperty(NSData())

		beforeEach {
			standardOutput.value = NSData()
			standardError.value = NSData()
		}

		it("should launch a task that writes to stdout") {
			let desc = TaskDescription(launchPath: "/bin/echo", arguments: [ "foobar" ])
			let promise = launchTask(desc, standardOutput: SinkOf(standardOutput))
			expect(standardOutput.value).to(equal(NSData()))

			let output = standardOutput.signal.scan(NSMutableData()) { (accum, data) in
				accum.appendData(data)
				return accum
			}

			expect(output.current.length).to(equal(0))

			let result = promise.await()
			expect(result).to(equal(0))

			expect(standardOutput.value).notTo(equal(NSData()))
			expect(NSString(data: output.current, encoding: NSUTF8StringEncoding)).to(equal("foobar\n"))
		}
	}
}
