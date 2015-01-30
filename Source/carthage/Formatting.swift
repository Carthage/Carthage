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
		return ColorOptions.colorful ? wrap(string) : string
	}
}

internal struct Formatting {

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

public enum ColorArgument: String, ArgumentType {
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
	
	public static let name = "color"
	
	public static func fromString(string: String) -> ColorArgument? {
		return self(rawValue: string.lowercaseString)
	}
	
}

public struct ColorOptions: OptionsType {
	public let argument: ColorArgument
	
	static var colorful: Bool {
		get {
			if Static.colorful == nil { fatalError("`ColorOptions.create` might not have been called…") }
			return Static.colorful!
		}
	}

	private struct Static {
		static var colorful: Bool? = nil
		static var token: dispatch_once_t = 0
	}
	
	public static func create(argument: ColorArgument) -> ColorOptions {
		dispatch_once(&Static.token) { Static.colorful = argument.isColorful }
		return self(argument: argument)
	}
	
	public static func evaluate(m: CommandMode) -> Result<ColorOptions> {
		return create
			<*> m <| Option(key: "color", defaultValue: ColorArgument.Auto, usage: "Terminal coloring and styling — values: ‘auto’ || ‘always’ || ‘never’")
	}
}
