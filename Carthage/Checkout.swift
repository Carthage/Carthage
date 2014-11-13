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
	public let function = "Check out the dependencies listed in a project's Cartfile.lock"

	public func run(mode: CommandMode) -> Result<()> {
		let directoryURL = NSURL.fileURLWithPath(NSFileManager.defaultManager().currentDirectoryPath)!

		return Project.loadFromDirectory(directoryURL)
			.flatMap { project in
				return checkoutLockedDependencies(project).wait()
			}
	}
}
