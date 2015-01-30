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

	static func quote(string: String) -> String {
		return Color.Wrap(foreground: .Green).autowrap("\u{0022}" + string + "\u{0022}")
	}
}

internal struct Terminal {
	static let term: String? = NSProcessInfo().environment["TERM"] as? String
	static let isDumb: Bool = (Terminal.term? as NSString?)?.isEqualToString("dumb") ?? false
	static let isTTY: Bool = isatty(1) == 1
}
