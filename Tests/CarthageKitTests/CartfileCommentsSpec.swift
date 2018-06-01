@testable import CarthageKit
import Nimble
import Quick

class CarfileCommentsSpec: QuickSpec {
	override func spec() {
		
		describe("removing carfile comments") {
			it("should not alter strings with no comments") {
				[
					"foo bar\nbaz",
					"",
					"\n",
					"this is a \"value\"",
					"\"value\" this is",
					"\"unclosed",
					"unopened\"",
					"I say \"hello\" you say \"goodbye\"!"
				]
				.forEach {
					expect($0.strippingTrailingCartfileComment) == $0
				}
			}
			
			it("should not alter strings with comment marker in quotes") {
				[
					"foo bar \"#baz\"",
					"\"#quotes\" is the new \"quotes\"",
					"\"#\""
				]
				.forEach {
					expect($0.strippingTrailingCartfileComment) == $0
				}
			}
			
			it("should remove comments") {
				expect("#".strippingTrailingCartfileComment)
					== ""
				expect("\n  #\n".strippingTrailingCartfileComment)
					== "\n  "
				expect("I have some #comments!".strippingTrailingCartfileComment)
					== "I have some "
				expect("Some don't \"#matter\" and some # do!".strippingTrailingCartfileComment)
					== "Some don't \"#matter\" and some "
				expect("\"a\" b# # \"c\" #".strippingTrailingCartfileComment)
					== "\"a\" b"
			}
		}
	}
}

