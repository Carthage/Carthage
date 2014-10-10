//
//  JSON.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit

internal protocol JSONDecodable {
	class func fromJSON(JSON: AnyObject) -> Result<Self>
}

internal func parseJSONAtURL<T: JSONDecodable>(URL: NSURL) -> Result<T> {
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
