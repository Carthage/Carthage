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

/// Wraps a string with terminal colors and formatting or passes it through, depending on `isColorful`.
private func wrap(_ isColorful: Bool, wrap: Color.Wrap) -> (String) -> String {
	return { string in
		return isColorful ? wrap.wrap(string) : string
	}
}

/// Argument for whether to color and format terminal output.
public enum ColorArgument: String, ArgumentProtocol, CustomStringConvertible {
	case auto = "auto"
	case never = "never"
	case always = "always"
	
	/// Whether to color and format.
	public var isColorful: Bool {
		switch self {
		case .always:
			return true
		case .never:
			return false
		case .auto:
			return Terminal.isTTY && !Terminal.isDumb
		}
	}
	
	public var description: String {
		return self.rawValue
	}
	
	public static let name = "color"
	
	public static func from(string: String) -> ColorArgument? {
		return self.init(rawValue: string.lowercased())
	}
}

/// Options for whether to color and format terminal output.
public struct ColorOptions: OptionsProtocol {
	let argument: ColorArgument
	let formatting: Formatting
	
	public struct Formatting {
		let isColorful: Bool
		let bullets: String
		let bulletin: Wrap
		let url: Wrap
		let projectName: Wrap
		let path: Wrap
		
		
		/// Wraps a string with terminal colors and formatting or passes it through.
		typealias Wrap = (_ string: String) -> String
		
		init(_ isColorful: Bool) {
			self.isColorful = isColorful
			bulletin      = wrap(isColorful, wrap: Color.Wrap(foreground: .blue, style: .bold))
			bullets       = bulletin("***") + " "
			url           = wrap(isColorful, wrap: Color.Wrap(styles: .underlined))
			projectName   = wrap(isColorful, wrap: Color.Wrap(styles: .bold))
			path          = wrap(isColorful, wrap: Color.Wrap(foreground: .yellow))
		}

		/// Wraps a string in bullets, one space of padding, and formatting.
		func bulletinTitle(_ string: String) -> String {
			return bulletin("*** " + string + " ***")
		}

		/// Wraps a string in quotation marks and formatting.
		func quote(_ string: String, quotationMark: String = "\"") -> String {
			return wrap(isColorful, wrap: Color.Wrap(foreground: .green))(quotationMark + string + quotationMark)
		}
	}
	
	public static func create(_ argument: ColorArgument) -> ColorOptions {
		return self.init(argument: argument, formatting: Formatting(argument.isColorful))
	}
	
	public static func evaluate(_ m: CommandMode) -> Result<ColorOptions, CommandantError<CarthageError>> {
		return create
			<*> m <| Option(key: "color", defaultValue: ColorArgument.auto, usage: "whether to apply color and terminal formatting (one of 'auto', 'always', or 'never')")
	}
}
