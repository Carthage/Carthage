//
//  Failure.swift
//  Quick
//
//  Created by Brian Ivan Gesiak on 6/28/14.
//  Copyright (c) 2014 Brian Ivan Gesiak. All rights reserved.
//

import Foundation

@objc class Failure {
    let callsite: Callsite
    let exception: NSException

    init(exception: NSException, callsite: Callsite) {
        self.exception = exception
        self.callsite = callsite
    }

    @objc(failureWithException:callsite:)
    class func failure(exception: NSException, callsite: Callsite) -> Failure {
        return Failure(exception: exception, callsite: callsite)
    }
}
