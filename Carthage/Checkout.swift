//
//  Checkout.swift
//  Carthage
//
//  Created by Alan Rogers on 11/10/2014.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa
import CarthageKit

public struct CheckoutCommand: CommandType {
	public let verb = "checkout"
	public let function = "Checkout dependencies listed in the project Cartfile"

	public func run(mode: CommandMode) -> Result<()> {
		// Identify the project's working directory.

		let pwd: String? = NSFileManager.defaultManager().currentDirectoryPath
		if pwd == nil || pwd!.isEmpty {
			return failure()
		}

		let project = Project(path: pwd!)
		return project.checkoutDependencies().wait()
	}
}
