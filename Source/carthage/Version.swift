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
import LlamaKit

public struct VersionCommand: CommandType {
	public let verb = "version"
	public let function = "Display the current version of Carthage"

	public func run(mode: CommandMode) -> Result<(), CommandantError> {
		switch mode {
		case let .Arguments:
			let versionString = NSBundle(identifier: CarthageKitBundleIdentifier)?.objectForInfoDictionaryKey("CFBundleShortVersionString") as String?
			if let semVer = SemanticVersion.fromScanner(NSScanner(string: versionString!)).value() {
				carthage.println(semVer)
			} else {
				return failure()
			}

		default:
			break
		}

		return success(())
	}
}
