//
//  Command.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit

protocol CommandType {
	class var verb: String { get }

	init<C: CollectionType where C.Generator.Element == String>(_ arguments: C)

	func run() -> Result<()>
}
