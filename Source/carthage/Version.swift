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

public struct VersionCommand: CommandType {
	public let verb = "version"
	public let function = "Display the current version of Carthage"

	private let printer: Printer

	public init(printer: Printer) {
		self.printer = printer
	}

	public func run(options: NoOptions<CarthageError>) -> Result<(), CarthageError> {
		let versionString = NSBundle(identifier: CarthageKitBundleIdentifier)?.objectForInfoDictionaryKey("CFBundleShortVersionString") as! String
		let semVer = SemanticVersion.fromScanner(NSScanner(string: versionString)).value
		printer.println(semVer!)
		return .Success(())
	}
}
