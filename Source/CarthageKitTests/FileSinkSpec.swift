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
		it("should open and write to a temporary file") {
			let result = FileSink<String>.openTemporaryFile().single()
			expect(result.isSuccess()).to(beTruthy())

			let sink = result.value().map { $0.0 }
			let URL = result.value().map { $0.1 } ?? NSURL.fileURLWithPath("URL-failed.txt")!

			sink?.put("foobar\n")
			expect(NSString(contentsOfURL: URL, encoding: NSUTF8StringEncoding, error: nil)).to(equal("foobar\n"))

			// Verify line buffering.
			sink?.put("fuzzbuzz")
			expect(NSString(contentsOfURL: URL, encoding: NSUTF8StringEncoding, error: nil)).to(equal("foobar\n"))

			// TODO: Verify output flushing.
			//sink?.put(.Completed)
			//expect(NSString(contentsOfURL: URL, encoding: NSUTF8StringEncoding, error: nil)).to(equal("foobar\nfuzzbuzz"))
		}

		it("should open stdout") {
			let sink = FileSink<String>.standardOutputSink()
			sink.put("foobar\n")
		}

		it("should open stderr") {
			let sink = FileSink<String>.standardErrorSink()
			sink.put("foobar\n")
		}
	}
}
