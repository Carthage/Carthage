//
//  Carthage.swift
//  Carthage
//
//  Created by Romain Pouclet on 2017-03-10.
//  Copyright © 2017 Carthage. All rights reserved.
//

import Foundation

public func carthageVersion() -> String {
	return Bundle(identifier: CarthageKitBundleIdentifier)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
}
