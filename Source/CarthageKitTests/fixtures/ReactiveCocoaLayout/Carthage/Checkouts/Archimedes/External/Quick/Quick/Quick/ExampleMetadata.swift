//
//  ExampleMetadata.swift
//  Quick
//
//  Created by Brian Gesiak on 8/22/14.
//  Copyright (c) 2014 Brian Ivan Gesiak. All rights reserved.
//

@objc public class ExampleMetadata {
    public let example: Example
    public let exampleIndex: Int

    init(example: Example, exampleIndex: Int) {
        self.example = example
        self.exampleIndex = exampleIndex
    }
}
