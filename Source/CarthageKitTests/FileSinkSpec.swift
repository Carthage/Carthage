//
//  FileSinkSpec.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2015-03-06.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import LlamaKit
import Nimble
import Quick
import ReactiveCocoa

class FileSinkSpec: QuickSpec {
	override func spec() {
		let foobarData: NSData = "foobar\n".dataUsingEncoding(NSUTF8StringEncoding)!
		let fuzzbuzzData: NSData = "fuzzbuzz".dataUsingEncoding(NSUTF8StringEncoding)!

		it("should open and write to a temporary file") {
			let result = FileSink.openTemporaryFile().single()
			expect(result.isSuccess()).to(beTruthy())

			let sink = result.value().map { $0.0 }
			let URL = result.value().map { $0.1 } ?? NSURL.fileURLWithPath("URL-failed.txt")!

			sink?.put(.Next(Box(foobarData)))
			expect(NSString(contentsOfURL: URL, encoding: NSUTF8StringEncoding, error: nil)).to(equal("foobar\n"))

			// Verify line buffering.
			sink?.put(.Next(Box(fuzzbuzzData)))
			expect(NSString(contentsOfURL: URL, encoding: NSUTF8StringEncoding, error: nil)).to(equal("foobar\n"))

			// Verify output flushing.
			sink?.put(.Completed)
			expect(NSString(contentsOfURL: URL, encoding: NSUTF8StringEncoding, error: nil)).to(equal("foobar\nfuzzbuzz"))
		}

		it("should open stdout") {
			let sink = FileSink.standardOutputSink()
			sink.put(.Next(Box(foobarData)))
			sink.put(.Completed)
		}

		it("should open stderr") {
			let sink = FileSink.standardErrorSink()
			sink.put(.Next(Box(foobarData)))
			sink.put(.Completed)
		}
	}
}
