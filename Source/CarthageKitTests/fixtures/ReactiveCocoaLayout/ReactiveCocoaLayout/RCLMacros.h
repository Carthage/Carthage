//
//  RCLMacros.h
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2013-05-04.
//  Copyright (c) 2013 GitHub. All rights reserved.
//

#import <Archimedes/Archimedes.h>
#import <ReactiveCocoa/ReactiveCocoa.h>

#ifdef RCL_FOR_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

// Creates a signal from a constant geometry value. The value must be a boolean,
// integral type, floating-point type, or a Core Graphics geometry structure.
//
// Returns a RACSignal.
#define RCLBox(VALUE) RCLBox(VALUE)

// Binds a view's frame to a set of attributes which describe different parts of
// the frame rectangle.
//
// This macro should be used on the left side of an equal sign, and the right
// side should be an NSDictionary containing RCL layout attributes, mapped to
// the signals or constant values to bind them to.
//
// The order that attributes are specified is irrelevant because dictionaries
// are always unordered. However, because there can be implicit dependencies in
// layout calculations (e.g., aligning the right side of a rectangle requires
// knowing its final width), attributes are applied in the following order:
//
//  1. `rcl_rect`
//  2. `rcl_size`, `rcl_origin`
//  3. `rcl_width`, `rcl_height`
//  4. `rcl_center`
//  5. `rcl_centerX`, `rcl_centerY`
//  6. `rcl_left`, `rcl_top`, `rcl_right`, `rcl_bottom`, `rcl_leading`, `rcl_trailing`
//  7. `rcl_baseline`
//
// The relative order of attributes that have the same priority is undefined.
//
// If `rcl_rect` is not specified, the view's `rcl_intrinsicBoundsSignal` is
// used as the basis for the layout. The provided attributes will simply
// overwrite parts of the intrinsic bounds, in the order specified above.
//
// Examples:
//
//  /*
//   * Sets the top of the view's frame to a constant 8 points, and puts the
//   * leading side of the rect after the trailing side of another view, plus
//   * 6 points of padding.
//   *
//   * The view's frame will always match its intrinsic size.
//   */
//  RCLFrame(view) = @{
//      rcl_top: @8,
//      rcl_leading: [otherView.rcl_trailingSignal plus:[RACSignal return:@6]]
//  };
//
//  /*
//   * Keeps the view at a constant 64 points wide, and centered at (100, 100).
//   *
//   * The view's height will always match its intrinsic size.
//   */
//  RCLFrame(view) = @{
//      rcl_width: @64,
//      rcl_center: MEDBox(CGPointMake(100, 100))
//  };
#define RCLFrame(VIEW) \
	[RCLRectAssignmentTrampoline trampolineWithView:(VIEW)][@"rcl_frame"]

// Like `RCLFrame`, but binds to the view's `rcl_alignmentRect` instead of its
// `rcl_frame`.
#define RCLAlignment(VIEW) \
	[RCLRectAssignmentTrampoline trampolineWithView:(VIEW)][@"rcl_alignmentRect"]

// Corresponds to a CGFloat or a signal thereof, which represents the position
// to align the left side of the rectangle to.
#define rcl_left @(RCLAttributeLeft)

// Corresponds to a CGFloat or a signal thereof, which represents the position
// to align the right side of the rectangle to.
#define rcl_right @(RCLAttributeRight)

// Corresponds to a CGFloat or a signal thereof, which represents the position
// to align the top side of the rectangle to.
#define rcl_top @(RCLAttributeTop)

// Corresponds to a CGFloat or a signal thereof, which represents the position
// to align the bottom side of the rectangle to.
#define rcl_bottom @(RCLAttributeBottom)

// Corresponds to a CGFloat or a signal thereof, which represents the position
// to align the leading side of the rectangle to.
#define rcl_leading @(RCLAttributeLeading)

// Corresponds to a CGFloat or a signal thereof, which represents the position
// to align the trailing side of the rectangle to.
#define rcl_trailing @(RCLAttributeTrailing)

// Corresponds to a CGFloat or a signal thereof, which represents the new width
// for the rectangle.
#define rcl_width @(RCLAttributeWidth)

// Corresponds to a CGFloat or a signal thereof, which represents the new height
// for the rectangle.
#define rcl_height @(RCLAttributeHeight)

// Corresponds to a CGFloat or a signal thereof, which represents the X position
// to align the center of the rectangle to.
#define rcl_centerX @(RCLAttributeCenterX)

// Corresponds to a CGFloat or a signal thereof, which represents the Y position
// to align the center of the rectangle to.
#define rcl_centerY @(RCLAttributeCenterY)

// Corresponds to a CGPoint or a signal thereof, which represents the position
// to align the center of the rectangle to.
#define rcl_center @(RCLAttributeCenter)

// Corresponds to a CGRect or a signal thereof, which represents the rectangle
// to use for layout.
#define rcl_rect @(RCLAttributeRect)

// Corresponds to a CGSize or a signal thereof, which represents the new size
// for the rectangle.
#define rcl_size @(RCLAttributeSize)

// Corresponds to a CGPoint or a signal thereof, which represents the new origin
// for the rectangle.
#define rcl_origin @(RCLAttributeOrigin)

// Corresponds to a view or a signal thereof, which will be used to adjust the
// rectangle so that both views' baselines are aligned.
//
// This should only be used with RCLAlignment, because baseline calculations are
// always relative to views' alignment rectangles.
#define rcl_baseline @(RCLAttributeBaseline)

@interface RCLRectAssignmentTrampoline : NSObject

#ifdef RCL_FOR_IPHONE
+ (instancetype)trampolineWithView:(UIView *)view;
#else
+ (instancetype)trampolineWithView:(NSView *)view;
#endif

- (RACSignal *)objectForKeyedSubscript:(NSString *)property;
- (void)setObject:(NSDictionary *)attributes forKeyedSubscript:(NSString *)property;

@end

// Do not use this directly. Use the `rcl_` keys above.
typedef enum : NSInteger {
	// Order is important here! It determines the order in which attributes are
	// applied (and overwritten) in a binding.
	RCLAttributeRect,
	RCLAttributeSize,
	RCLAttributeOrigin,
	RCLAttributeHeight,
	RCLAttributeWidth,
	RCLAttributeCenter,
	RCLAttributeCenterX,
	RCLAttributeCenterY,
	RCLAttributeBottom,
	RCLAttributeRight,
	RCLAttributeTop,
	RCLAttributeLeft,
	RCLAttributeTrailing,
	RCLAttributeLeading,
	RCLAttributeBaseline
} RCLAttribute;

#define RCLBox_struct_(TYPE) \
    __attribute__((overloadable)) static inline RACSignal *RCLBox(TYPE value) { \
        return [RACSignal return:MEDBox(value)]; \
    }

#define RCLBox_number_(TYPE) \
    __attribute__((overloadable)) static inline RACSignal *RCLBox(TYPE value) { \
        return [RACSignal return:@(value)]; \
    }

RCLBox_struct_(CGRect);
RCLBox_struct_(CGSize);
RCLBox_struct_(CGPoint);
RCLBox_number_(signed char);
RCLBox_number_(unsigned char);
RCLBox_number_(short);
RCLBox_number_(unsigned short);
RCLBox_number_(int);
RCLBox_number_(unsigned);
RCLBox_number_(long);
RCLBox_number_(unsigned long);
RCLBox_number_(long long);
RCLBox_number_(unsigned long long);
RCLBox_number_(float);
RCLBox_number_(double);
