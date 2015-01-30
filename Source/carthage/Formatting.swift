//
//  Formatting.swift
//  Carthage
//
//  Created by J.D. Healy on 1/29/15.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import Commandant
import Foundation
import LlamaKit
import PrettyColors
import ReactiveCocoa

extension Color.Wrap {
	func autowrap(string: String) -> String {
		return Formatting.color ? self.wrap(string) : string
	}
}

internal struct Formatting {
	static let color = Terminal.isTTY && !Terminal.isDumb

	static let bulletin = Color.Wrap(foreground: .Blue, style: .Bold)
	static let bullets: String = {
		return bulletin.autowrap("***") + " "
	}()

	static let URL = [StyleParameter.Underlined] as Color.Wrap
	static let projectName = [StyleParameter.Bold] as Color.Wrap
	static let path = Color.Wrap(foreground: .Yellow)
	
	static func quote(string: String, quotationMark: String = "\u{0022}" /* double quote */) -> String {
		return Color.Wrap(foreground: .Green).autowrap(quotationMark + string + quotationMark)
	}
}

internal struct Terminal {
	static let term: String? = getEnvironmentVariable("TERM").value()
	static let isDumb: Bool = (Terminal.term?.lowercaseString as NSString?)?.isEqualToString("dumb") ?? false
	static let isTTY: Bool = isatty(STDOUT_FILENO) == 1
}
