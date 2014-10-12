//
//  Project.swift
//  Carthage
//
//  Created by Alan Rogers on 12/10/2014.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit

/// Represents a Project that is using Carthage.
public struct Project {
	/// Path to the root folder
    public var projectPath: String

	/// The project's cart file
	public var cartFile: Cartfile?

	public init(projectPath: String) {
		self.projectPath = projectPath

		let cartFileURL : NSURL? = NSURL.fileURLWithPath(self.projectPath)?.URLByAppendingPathComponent("Cartfile")

		if (cartFileURL != nil) {
			let result : Result<Cartfile> = parseJSONAtURL(cartFileURL!)

			if (result.error() != nil) {
				return
			}

			cartFile = result.value()
		}
	}
}
