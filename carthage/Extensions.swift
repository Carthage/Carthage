//
//  Extensions.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-11-26.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

// This file contains extensions to anything that's not appropriate for
// CarthageKit.

import Foundation
import ReactiveCocoa

private let outputScheduler = QueueScheduler(DISPATCH_QUEUE_PRIORITY_HIGH)

/// A thread-safe version of Swift's standard println().
internal func println() {
	outputScheduler.schedule {
		Swift.println()
	}
}

/// A thread-safe version of Swift's standard println().
internal func println<T>(object: T) {
	outputScheduler.schedule {
		Swift.println(object)
	}
}

/// A thread-safe version of Swift's standard print().
internal func print<T>(object: T) {
	outputScheduler.schedule {
		Swift.print(object)
	}
}
