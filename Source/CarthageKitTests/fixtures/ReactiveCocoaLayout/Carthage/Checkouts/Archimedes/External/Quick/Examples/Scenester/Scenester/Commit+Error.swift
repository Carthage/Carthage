//
//  Commit+Error.swift
//  Scenester
//
//  Created by Brian Ivan Gesiak on 6/10/14.
//  Copyright (c) 2014 Brian Ivan Gesiak. All rights reserved.
//

import Foundation

public let CommitErrorDomain = "CommitErrorDomain"
public enum CommitErrorCode: Int {
    case NoCommits, InvalidCommit, InvalidResponse
}

extension Commit {
    public static func commitError(code: CommitErrorCode) -> NSError {
        switch code {
        case .NoCommits:
            return NSError(domain: CommitErrorDomain, code: code.toRaw(),
                userInfo: [NSLocalizedDescriptionKey: "The repo does not have any commits."])
        case .InvalidCommit:
            return NSError(domain: CommitErrorDomain, code: code.toRaw(),
                userInfo: [NSLocalizedDescriptionKey: "The commit JSON is invalid."])
        case .InvalidResponse:
            return NSError(domain: CommitErrorDomain, code: code.toRaw(),
                userInfo: [NSLocalizedDescriptionKey: "The response JSON for that repo does not contain commit data."])
        }
    }
}