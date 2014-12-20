//
//  NSCell+RCLGeometryAdditions.h
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-30.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class RACSignal;

@interface NSCell (RCLGeometryAdditions)

// Observes the receiver's -cellSize for changes.
//
// The receiver must have a controlView at the time this method is invoked.
// Changing the receiver's controlView while the returned signal is being used
// will result in undefined behavior.
//
// Returns a signal which sends the current cell size, and a new CGSize every
// time the cell's intrinsic content size is invalidated.
- (RACSignal *)rcl_sizeSignal;

// Observes the receiver's -cellSizeForBounds: for changes.
//
// The receiver must have a controlView at the time this method is invoked.
// Changing the receiver's controlView while the returned signal is being used
// will result in undefined behavior.
//
// boundsSignal - A signal of CGRect values, representing the bounds rectangles
//                to get the cell size for.
//
// Returns a signal which sends the receiver's -cellSizeForBounds: the first
// time `boundsSignal` sends a value, then a new CGSize every time the cell's
// intrinsic content size is invalidated or another value is sent on
// `boundsSignal`.
- (RACSignal *)rcl_sizeSignalForBounds:(RACSignal *)boundsSignal;

@end
