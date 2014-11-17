//
//  Poet.swift
//  Quick
//
//  Created by Brian Ivan Gesiak on 6/6/14.
//  Copyright (c) 2014 Brian Ivan Gesiak. All rights reserved.
//

class Poet: Person {
    override var greeting: String {
        get {
            if isHappy {
                return "Oh, joyous day!"
            } else {
                return "Woe is me!"
            }
        }
    }
}
