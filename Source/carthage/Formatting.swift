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

func wrap(colorful: Bool)(wrap: Color.Wrap)(string: String) -> String {
	return colorful ? wrap.wrap(string) : string
}

internal struct Terminal {
	static var term: String? {
		return getEnvironmentVariable("TERM").value()
	}
	static var isDumb: Bool {
		return (Terminal.term?.lowercaseString as NSString?)?.isEqualToString("dumb") ?? false
	}
	static var isTTY: Bool {
		return isatty(STDOUT_FILENO) == 1
	}
}

public enum ColorArgument: String, ArgumentType, Printable {
	case Auto = "auto"
	case Never = "never"
	case Always = "always"
	
	public var isColorful: Bool {
		switch self {
		case .Always:
			return true
		case .Never:
			return false
		case .Auto:
			return Terminal.isTTY && !Terminal.isDumb
		}
	}
	
	public var description: String {
		return "‘auto’ || ‘always’ || ‘never’"
	}
	
	public static let name = "color"
	
	public static func fromString(string: String) -> ColorArgument? {
		return self(rawValue: string.lowercaseString)
	}
	
}

public struct ColorOptions: OptionsType {
	let argument: ColorArgument
	let formatting: Formatting
	
	struct Formatting {
		let colorful: Bool
		
		typealias Wrap = (string: String) -> String
		
		init(_ colorful: Bool) {
			self.colorful    = colorful
			self.bulletin    = wrap(colorful)(wrap: Color.Wrap(foreground: .Blue, style: .Bold))
			self.bullets     = self.bulletin(string: "***") + " "
			self.URL         = wrap(colorful)(wrap: Color.Wrap(styles: .Underlined))
			self.projectName = wrap(colorful)(wrap: Color.Wrap(styles: .Bold))
			self.path        = wrap(colorful)(wrap: Color.Wrap(foreground: .Yellow))
		}
		
		let bulletin: Wrap
		let bullets: String
		
		let URL: Wrap
		let projectName: Wrap
		let path: Wrap
		
		func quote(string: String, quotationMark: String = "\"") -> String {
			return wrap(colorful)(wrap: Color.Wrap(foreground: .Green))(string: quotationMark + string + quotationMark)
		}
		
	}
	
	static func create(argument: ColorArgument) -> ColorOptions {
		return self(argument: argument, formatting: Formatting(argument.isColorful))
	}
	
	public static func evaluate(m: CommandMode) -> Result<ColorOptions> {
		return create
			<*> m <| Option(key: "color", defaultValue: ColorArgument.Auto, usage: "whether to apply formatting and colors to terminal messages")
	}
}
