//
//  NSControl+RCLGeometryAdditions.h
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-30.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class RACSignal;

@interface NSControl (RCLGeometryAdditions)

// Observes the cell(s) of the receiver for changes to their intrinsic content
// size.
//
// Returns a signal which sends each NSCell that is invalidated.
- (RACSignal *)rcl_cellIntrinsicContentSizeInvalidatedSignal;

@end
