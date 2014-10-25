//
//  Checkout.swift
//  Carthage
//
//  Created by Alan Rogers on 11/10/2014.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import CarthageKit

struct CheckoutCommand: CommandType {
	static let verb = "checkout"

	init() {
	}

	init<S: SequenceType where S.Generator.Element == String>(_ arguments: S) {
	}

	func run() -> Result<()> {
		// 1. Identify the project's working directory.

		let pwd : String? = NSFileManager.defaultManager().currentDirectoryPath;
		if pwd == nil || pwd!.isEmpty {
			return failure()
		}

		// 2. Create the project

		let project = Project(path: pwd!)

		return project.cloneDependencies()
	}
}
