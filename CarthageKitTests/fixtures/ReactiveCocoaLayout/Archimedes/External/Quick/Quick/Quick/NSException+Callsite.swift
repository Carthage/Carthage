//
//  NSException+Callsite.swift
//  Quick
//
//  Created by Brian Ivan Gesiak on 6/28/14.
//  Copyright (c) 2014 Brian Ivan Gesiak. All rights reserved.
//

import Foundation

let FilenameKey = "SenTestFilenameKey"
let LineNumberKey = "SenTestLineNumberKey"

extension NSException {
    var qck_callsite: Callsite? {
        if let info: NSDictionary = userInfo {
            if let file = info[FilenameKey] as? String {
                if let line = info[LineNumberKey] as? Int {
                    return Callsite(file: file, line: line)
                }
            }
        }

        return nil
    }
}
