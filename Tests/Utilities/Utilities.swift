//
//  Utilities.swift
//  CarthageTests
//
//  Created by J.D. Healy on 2/22/15.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa

//------------------------------------------------------------------------------
// MARK: - Bundle
//------------------------------------------------------------------------------

class BundleLocator {}

let bundle = NSBundle(forClass: BundleLocator().dynamicType)

internal func stringify(data: NSData) -> Result<String> {
  return (NSString(data: data, encoding: NSUTF8StringEncoding) as? String).map(success)
    ?? Error.StringifyData.failure("Failed to convert NSData to UTF-8 string.")
}

//------------------------------------------------------------------------------
// MARK: - Extensions
//------------------------------------------------------------------------------

extension ColdSignal {

  /// Performs the given action upon each value in the receiver, bailing out
  /// with an error if a given action fails.
  internal func try<U>(f: T -> Result<U>) -> ColdSignal {
    return mergeMap { value in
      switch f(value) {
      case .Success:
        return .single(value)
      case let .Failure(error):
        return .error(error)
      }
    }
  }

}
