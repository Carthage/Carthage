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
