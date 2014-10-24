//
//  Help.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa

struct HelpCommand: CommandType {
	let verb = "help"

	func run<C: CollectionType where C.Generator.Element == String>(arguments: C) -> ColdSignal<()> {
		println("ohai help")
		return .empty()
	}
}
