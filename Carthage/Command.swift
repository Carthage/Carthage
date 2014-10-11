//
//  Command.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation

protocol CommandType {
	var verb: String { get }

	func run(arguments: [String])
}
