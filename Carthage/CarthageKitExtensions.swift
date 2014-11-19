//
//  CarthageKitExtensions.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-18.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

// This file contains extensions to CarthageKit, for use by the Carthage command
// line tool. Generally, these extensions are not general enough to include in
// the framework itself.

import CarthageKit
import Foundation
import ReactiveCocoa

/// Logs project events put into the sink.
internal struct ProjectEventSink: SinkType {
	mutating func put(event: ProjectEvent) {
		switch event {
		case let .Cloning(project):
			println("*** Cloning \(project.name)")

		case let .Fetching(project):
			println("*** Fetching \(project.name)")

		case let .CheckingOut(project, revision):
			println("*** Checking out \(project.name) at \"\(revision)\"")
		}
	}
}
