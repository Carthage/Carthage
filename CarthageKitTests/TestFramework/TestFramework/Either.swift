//
//  Either.swift
//  TestFramework
//
//  Created by Justin Spahr-Summers on 2014-11-08.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation

public enum Either<A, B> {
	case Left(() -> A)
	case Right(() -> B)
}