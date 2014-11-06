//
//  FrameworkExtensions.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-31.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa

extension String {
	/// Returns a signal that will enumerate each line of the receiver, then
	/// complete.
	public var linesSignal: ColdSignal<String> {
		return ColdSignal { subscriber in
			(self as NSString).enumerateLinesUsingBlock { (line, stop) in
				subscriber.put(.Next(Box(line as String)))

				if subscriber.disposable.disposed {
					stop.memory = true
				}
			}

			subscriber.put(.Completed)
		}
	}
}

/// Merges `rhs` into `lhs` and returns the result.
public func combineDictionaries<K, V>(lhs: [K: V], rhs: [K: V]) -> [K: V] {
	var result = lhs
	for (key, value) in rhs {
		result.updateValue(value, forKey: key)
	}

	return result
}
