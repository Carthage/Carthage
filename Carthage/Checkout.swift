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
		println("ohai checkout")

		// 1. Identify the current project's working directory.

		let pwd : String = NSFileManager.defaultManager().currentDirectoryPath;
		if pwd.isEmpty {
			return failure()
		}
		println("pwd is: \(pwd)")

		return success()
	}
}
