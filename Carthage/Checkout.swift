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

struct CheckoutCommand: CommandType {
	let verb = "checkout"

	func run<C: CollectionType where C.Generator.Element == String>(arguments: C) -> ColdSignal<()> {
		// Identify the project's working directory.

		let pwd : String? = NSFileManager.defaultManager().currentDirectoryPath
		if pwd == nil || pwd!.isEmpty {
			return ColdSignal.empty()
		}

		let project = Project(path: pwd!)
		return project.checkoutDependencies()
	}
}
