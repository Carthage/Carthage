//
//  Formatting.swift
//  Carthage
//
//  Created by J.D. Healy on 1/29/15.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import CarthageKit
import Commandant
import Foundation
import Result
import PrettyColors

/// Wraps a string with terminal colors and formatting or passes it through, depending on `colorful`.
private func wrap(colorful: Bool, wrap: Color.Wrap) -> String -> String {
	return { string in
		return colorful ? wrap.wrap(string) : string
	}
}

/// Argument for whether to color and format terminal output.
public enum ColorArgument: String, ArgumentType, CustomStringConvertible {
	case Auto = "auto"
	case Never = "never"
	case Always = "always"
	
	/// Whether to color and format.
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
		return self.rawValue
	}
	
	public static let name = "color"
	
	public static func fromString(string: String) -> ColorArgument? {
		return self.init(rawValue: string.lowercaseString)
	}
	
}

/// Options for whether to color and format terminal output.
public struct ColorOptions: OptionsType {
	let argument: ColorArgument
	let formatting: Formatting
	
	public struct Formatting {
		let colorful: Bool
		let bullets: String
		let bulletin: Wrap
		let URL: Wrap
		let projectName: Wrap
		let path: Wrap
		
		
		/// Wraps a string with terminal colors and formatting or passes it through.
		typealias Wrap = (string: String) -> String
		
		init(_ colorful: Bool) {
			self.colorful = colorful
			bulletin      = wrap(colorful, wrap: Color.Wrap(foreground: .Blue, style: .Bold))
			bullets       = bulletin(string: "***") + " "
			URL           = wrap(colorful, wrap: Color.Wrap(styles: .Underlined))
			projectName   = wrap(colorful, wrap: Color.Wrap(styles: .Bold))
			path          = wrap(colorful, wrap: Color.Wrap(foreground: .Yellow))
		}

		/// Wraps a string in bullets, one space of padding, and formatting.
		func bulletinTitle(string: String) -> String {
			return bulletin(string: "*** " + string + " ***")
		}

		/// Wraps a string in quotation marks and formatting.
		func quote(string: String, quotationMark: String = "\"") -> String {
			return wrap(colorful, wrap: Color.Wrap(foreground: .Green))(quotationMark + string + quotationMark)
		}
	}
	
	public static func create(argument: ColorArgument) -> ColorOptions {
		return self.init(argument: argument, formatting: Formatting(argument.isColorful))
	}
	
	public static func evaluate(m: CommandMode) -> Result<ColorOptions, CommandantError<CarthageError>> {
		return create
			<*> m <| Option(key: "color", defaultValue: ColorArgument.Auto, usage: "whether to apply color and terminal formatting (one of ‘auto’, ‘always’, or ‘never’)")
	}
}
