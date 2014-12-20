//
//  GitHub.swift
//  Scenester
//
//  Created by Brian Ivan Gesiak on 6/10/14.
//  Copyright (c) 2014 Brian Ivan Gesiak. All rights reserved.
//

import Foundation

public struct Commit {
    public let message: String
    public let author: String
    
    public var simpleDescription: String { get { return "\(author): '\(message)'" } }
    
    public init(message: String, author: String) {
        self.message = message
        self.author = author
    }
}
