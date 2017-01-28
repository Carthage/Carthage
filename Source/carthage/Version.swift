//
//  Version.swift
//  Carthage
//
//  Created by Robert Böhnke on 19/11/14.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Commandant
import Foundation
import Result

public struct VersionCommand: CommandProtocol {
	public let verb = "version"
	public let function = "Display the current version of Carthage"

	public func run(_ options: NoOptions<CarthageError>) -> Result<(), CarthageError> {
		let versionString = Bundle(identifier: CarthageKitBundleIdentifier)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
		carthage.println(versionString)
		return .success(())
	}
}
