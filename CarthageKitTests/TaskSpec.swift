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
		let standardOutput = ObservableProperty(NSData())
		let standardError = ObservableProperty(NSData())

		beforeEach {
			standardOutput.value = NSData()
			standardError.value = NSData()
		}

		func accumulatingSinkForProperty(property: ObservableProperty<NSData>) -> SinkOf<NSData> {
			let (signal, sink) = HotSignal<NSData>.pipe()

			signal.scan(initial: NSData()) { (accum, data) in
				println("received data to accumulate")

				let buffer = accum.mutableCopy() as NSMutableData
				buffer.appendData(data)

				return buffer
			// FIXME: This doesn't actually need to be cold, it just works
			// around memory management issues.
			}.replay(0).start(next: { value in
				property.value = value
			})

			return sink
		}

		it("should launch a task that writes to stdout") {
			let desc = TaskDescription(launchPath: "/bin/echo", arguments: [ "foobar" ])
			let task = launchTask(desc, standardOutput: accumulatingSinkForProperty(standardOutput)).on(subscribed: { println("subscribed") }, next: { value in println("next \(value)") }, terminated: { println("terminated") })
			expect(standardOutput.value).to(equal(NSData()))

			let result = task.wait()
			expect(result.isSuccess()).to(beTruthy())
			expect(NSString(data: standardOutput.value, encoding: NSUTF8StringEncoding)).to(equal("foobar\n"))
		}

		it("should launch a task that writes to stderr") {
			let desc = TaskDescription(launchPath: "/usr/bin/stat", arguments: [ "not-a-real-file" ])
			let task = launchTask(desc, standardError: accumulatingSinkForProperty(standardError))
			expect(standardError.value).to(equal(NSData()))

			let result = task.wait()
			expect(result.isSuccess()).to(beFalsy())
			expect(NSString(data: standardError.value, encoding: NSUTF8StringEncoding)).to(equal("stat: not-a-real-file: stat: No such file or directory\n"))
		}

		it("should launch a task with standard input") {
			let strings = [ "foo\n", "bar\n", "buzz\n", "fuzz\n" ]
			let data = strings.map { $0.dataUsingEncoding(NSUTF8StringEncoding)! }

			let desc = TaskDescription(launchPath: "/usr/bin/sort", standardInput: ColdSignal.fromValues(data))
			let task = launchTask(desc, standardOutput: accumulatingSinkForProperty(standardOutput))

			let result = task.wait()
			expect(result.isSuccess()).to(beTruthy())
			expect(NSString(data: standardOutput.value, encoding: NSUTF8StringEncoding)).to(equal("bar\nbuzz\nfoo\nfuzz\n"))
		}
	}
}
