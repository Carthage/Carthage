//
//  JSON.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit

/// Implemented by any type that can be parsed from JSON.
public protocol JSONDecodable {
	/// Attempts to parse an instance of this type from the given JSON object.
	class func fromJSON(JSON: AnyObject) -> Result<Self>
}

/// Loads the JSON file at the given URL and attempts to parse it into an
/// instance of type `T`.
public func parseJSONAtURL<T: JSONDecodable>(URL: NSURL) -> Result<T> {
	var error: NSError?
	if let data = NSData(contentsOfURL: URL, options: NSDataReadingOptions.allZeros, error: &error) {
		if let object: AnyObject = NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.allZeros, error: &error) {
			return T.fromJSON(object)
		} else if let error = error {
			return failure(error)
		}
	} else if let error = error {
		return failure(error)
	}

	return failure()
}
