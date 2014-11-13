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

		return ColdSignal.fromResult(CheckoutOptions.evaluate(mode))
			.map { options -> ColdSignal<()> in
				return ColdSignal.fromResult(Project.loadFromDirectory(directoryURL))
					.map { $0.checkoutLockedDependencies() }
					.merge(identity)
			}
			.merge(identity)
			.wait()
	}
}

private struct CheckoutOptions: OptionsType {
	static func evaluate(m: CommandMode) -> Result<CheckoutOptions> {
		switch m {
		case let .Usage:
			return failure(CarthageError.InvalidArgument(description: "").error)

		default:
			return success(self())
		}
	}
}
