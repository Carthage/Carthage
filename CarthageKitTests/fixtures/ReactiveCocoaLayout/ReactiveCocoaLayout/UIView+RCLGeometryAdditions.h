//
//  UIView+RCLGeometryAdditions.h
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-13.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RACSignal;

@interface UIView (RCLGeometryAdditions)

// The alignment rect for the receiver's current frame.
//
// Setting this property will adjust the receiver's frame such that the
// alignment rect matches the new value, before the frame is aligned to the
// receiver's backing store.
//
// This property may have `RAC()` bindings applied to it, but it is not
// KVO-compliant. Use -rcl_alignmentRectSignal for observing changes instead.
@property (nonatomic, assign) CGRect rcl_alignmentRect;

// The receiver's current frame.
//
// Setting this property to a given rect will automatically align the rect with
// pixels on the screen.
//
// This property may have `RAC()` bindings applied to it, but it is not
// KVO-compliant. Use -rcl_frameSignal for observing changes instead.
@property (nonatomic, assign) CGRect rcl_frame;

// The receiver's current bounds.
//
// Setting this property to a given rect will automatically align the rect with
// pixels on the screen.
//
// This property may have `RAC()` bindings applied to it, but it is not
// KVO-compliant. Use -rcl_boundsSignal for observing changes instead.
@property (nonatomic, assign) CGRect rcl_bounds;

// Observes the receiver's `bounds` for changes.
//
// Returns a signal which sends the current and all future values for `bounds`.
- (RACSignal *)rcl_boundsSignal;

// Observes the receiver's `frame` for changes.
//
// Returns a signal which sends the current and all future values for `frame`.
- (RACSignal *)rcl_frameSignal;

// Observes the receiver's baseline for changes.
//
// This observes the bounds of the receiver and the frame of the receiver's
// -viewForBaselineLayout, and recalculates the offset of the baseline from the
// maximum Y edge whenever either changes.
//
// **Note:** This method may sometimes return incorrect results because
// -viewForBaselineLayout isn't actually intended to be used outside of Auto
// Layout. See http://www.openradar.me/radar?id=2468401 for more information.
//
// Returns a signal of baseline offsets from the maximum Y edge of the view.
- (RACSignal *)rcl_baselineSignal;

@end
