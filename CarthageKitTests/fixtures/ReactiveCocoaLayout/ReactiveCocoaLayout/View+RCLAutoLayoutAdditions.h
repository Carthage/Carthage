//
//  View+RCLAutoLayoutAdditions.h
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-17.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#ifdef RCL_FOR_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

@class RACSignal;

// Extensions to UIView on iOS and NSView on OS X, depending only on
// cross-platform Auto Layout APIs.
#ifdef RCL_FOR_IPHONE
@interface UIView (RCLAutoLayoutAdditions)
#else
@interface NSView (RCLAutoLayoutAdditions)
#endif

// Observes the receiver's `intrinsicContentSize` for changes.
//
// Returns a signal which sends the current and all future values for
// `intrinsicContentSize`.
- (RACSignal *)rcl_intrinsicContentSizeSignal;

// Like -rcl_intrinsicContentSizeSignal, but sends rectangles originating at (0, 0).
- (RACSignal *)rcl_intrinsicBoundsSignal;

// Like -rcl_intrinsicContentSizeSignal, but only sends the height.
- (RACSignal *)rcl_intrinsicHeightSignal;

// Like -rcl_intrinsicContentSizeSignal, but only sends the width.
- (RACSignal *)rcl_intrinsicWidthSignal;

// Observes the receiver's alignment rect for changes.
//
// Returns a signal which sends the current alignment rect, and a new CGRect
// every time the view's frame changes in a way that might affect the alignment
// rect.
- (RACSignal *)rcl_alignmentRectSignal;

@end
