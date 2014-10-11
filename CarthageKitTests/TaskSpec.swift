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

		func accumulateData(signal: Signal<NSData>) -> Signal<NSData> {
			return signal.scan(NSData()) { (accum, data) in
				let buffer = accum.mutableCopy() as NSMutableData
				buffer.appendData(data)

				return buffer
			}
		}

		it("should launch a task that writes to stdout") {
			let desc = TaskDescription(launchPath: "/bin/echo", arguments: [ "foobar" ])
			let promise = launchTask(desc, standardOutput: SinkOf(standardOutput))
			expect(standardOutput.value).to(equal(NSData()))

			let output = accumulateData(standardOutput.signal)
			expect(output.current.length).to(equal(0))

			let result = promise.await()
			expect(result).to(equal(EXIT_SUCCESS))

			expect(standardOutput.value).notTo(equal(NSData()))
			expect(NSString(data: output.current, encoding: NSUTF8StringEncoding)).to(equal("foobar\n"))
		}

		it("should launch a task that writes to stderr") {
			let desc = TaskDescription(launchPath: "/usr/bin/stat", arguments: [ "not-a-real-file" ])
			let promise = launchTask(desc, standardError: SinkOf(standardError))
			expect(standardError.value).to(equal(NSData()))

			let errors = accumulateData(standardError.signal)
			expect(errors.current.length).to(equal(0))

			let result = promise.await()
			expect(result).to(equal(EXIT_FAILURE))

			expect(standardError.value).notTo(equal(NSData()))
			expect(NSString(data: errors.current, encoding: NSUTF8StringEncoding)).to(equal("stat: not-a-real-file: stat: No such file or directory\n"))
		}

		it("should launch a task with standard input") {
			let desc = TaskDescription(launchPath: "/usr/bin/sort")

			let strings = [ "foo\n", "bar\n", "buzz\n", "fuzz\n" ]
			let data = strings.map { $0.dataUsingEncoding(NSUTF8StringEncoding)! }

			let promise = launchTask(desc, standardInput: SequenceOf(data), standardOutput: SinkOf(standardOutput))
			let output = accumulateData(standardOutput.signal)

			let result = promise.await()
			expect(result).to(equal(EXIT_SUCCESS))
			expect(NSString(data: output.current, encoding: NSUTF8StringEncoding)).to(equal("bar\nbuzz\nfoo\nfuzz\n"))
		}
	}
}
