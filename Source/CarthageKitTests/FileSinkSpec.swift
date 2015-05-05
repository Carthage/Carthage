//
//  FileSinkSpec.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2015-03-06.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import Box
import CarthageKit
import Foundation
import Result
import Nimble
import Quick
import ReactiveCocoa

class FileSinkSpec: QuickSpec {
	override func spec() {
		it("should open and write to a temporary file") {
			let result = FileSink<String>.openTemporaryFile() |> single
			expect(result).notTo(beNil())
			expect(result?.value).notTo(beNil())

			let sink = result?.value.map { $0.0 }
			let URL = result?.value.map { $0.1 } ?? NSURL.fileURLWithPath("URL-failed.txt")!

			sink?.put(.Next(Box("foobar\n")))
			expect(NSString(contentsOfURL: URL, encoding: NSUTF8StringEncoding, error: nil)).to(equal("foobar\n"))

			// Verify line buffering.
			sink?.put(.Next(Box("fuzzbuzz")))
			expect(NSString(contentsOfURL: URL, encoding: NSUTF8StringEncoding, error: nil)).to(equal("foobar\n"))

			sink?.put(.Completed)
			expect(NSString(contentsOfURL: URL, encoding: NSUTF8StringEncoding, error: nil)).to(equal("foobar\nfuzzbuzz"))
		}

		it("should open stdout") {
			let sink = FileSink<String>.standardOutputSink()
			sink.put(.Next(Box("foobar\n")))
			sink.put(.Completed)
		}

		it("should open stderr") {
			let sink = FileSink<String>.standardErrorSink()
			sink.put(.Next(Box("foobar\n")))
			sink.put(.Completed)
		}
	}
}
