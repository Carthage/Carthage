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

	init(_ arguments: [String] = []) {
	}

	func run() -> Result<()> {
		// 1. Identify the current project's working directory.

		let pwd : String? = NSFileManager.defaultManager().currentDirectoryPath;
		if pwd == nil || pwd!.isEmpty {
			return failure()
		}

		// 2. Create project

		let project = Project(path: pwd!)

		println("project cartfile is: \(project.cartfile)")

		return success()
	}
}
