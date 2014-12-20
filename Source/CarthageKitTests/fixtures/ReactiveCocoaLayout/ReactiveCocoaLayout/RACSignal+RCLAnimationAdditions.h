//
//  RACSignal+RCLAnimationAdditions.h
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2013-01-04.
//  Copyright (c) 2013 GitHub. All rights reserved.
//

#import <ReactiveCocoa/ReactiveCocoa.h>

// Defines the curve (timing function) for an animation.
//
// RCLAnimationCurveDefault   - The default or inherited animation curve.
// RCLAnimationCurveEaseInOut - Begins the animation slowly, speeds up in the
//                              middle, and then slows to a stop.
// RCLAnimationCurveEaseIn    - Begins the animation slowly and speeds up to
//                              a stop.
// RCLAnimationCurveEaseOut   - Begins the animation quickly and slows down to
//                              a stop.
// RCLAnimationCurveLinear    - Animates with the same pace over the duration of
//                              the animation.
#ifdef RCL_FOR_IPHONE
    typedef enum {
        RCLAnimationCurveDefault = 0,
        RCLAnimationCurveEaseInOut = UIViewAnimationOptionCurveEaseInOut,
        RCLAnimationCurveEaseIn = UIViewAnimationOptionCurveEaseIn,
        RCLAnimationCurveEaseOut = UIViewAnimationOptionCurveEaseOut,
        RCLAnimationCurveLinear = UIViewAnimationOptionCurveLinear
    } RCLAnimationCurve;
#else
    typedef enum : NSUInteger {
        RCLAnimationCurveDefault,
        RCLAnimationCurveEaseInOut,
        RCLAnimationCurveEaseIn,
        RCLAnimationCurveEaseOut,
        RCLAnimationCurveLinear
    } RCLAnimationCurve;
#endif

// Determines whether the calling code is running from within -animate (or
// a variant thereof).
//
// This can be used to conditionalize behavior based on whether a signal
// somewhere in the chain is supposed to be animated.
//
// This function is thread-safe.
extern BOOL RCLIsInAnimatedSignal(void);

@interface RACSignal (RCLAnimationAdditions)

// Behaves like -animatedSignalsWithDuration: with the system's default
// animation duration.
- (RACSignal *)animatedSignals;

// Invokes -animatedSignalsWithDuration:curve: with a curve of
// RCLAnimationCurveDefault.
- (RACSignal *)animatedSignalsWithDuration:(NSTimeInterval)duration;

// Wraps every next in an animation, using the default duration and animation
// curve, and captures each animation in an inner signal.
//
// On iOS, how you combine the inner signals determines whether animations are
// interruptible:
//
//  - Concatenating the inner signals will result in new animations only
//    beginning after all previous animations have completed.
//  - Flattening or switching the inner signals will start new animations as
//    soon as possible, and use the current (in progress) UI state for
//    animating.
//
// On OS X, `NSView` animations are always serialized.
//
// Combining the inner signals, and binding the resulting signal of values to
// a view property, will result in updates to that property (that originate from
// the signal) being automatically animated.
//
// To delay an animation, use -[RACSignal delay:] or -[RACSignal throttle:] on
// the receiver _before_ using this method. Because the aforementioned methods
// delay delivery of `next`s, applying them _after_ this method may cause
// values to be delivered outside of any animation block.
//
// Examples
//
//   RAC(self.textField, alpha, @1) = [[alphaValues
//		animatedSignalsWithDuration:0.2]
//		/* Animate changes to the alpha without interruption. */
//		concat];
//
//	RAC(self.button, alpha, @1) = [[[alphaValues
//		/* Delay animations by 0.1 seconds. */
//		delay:0.1]
//		animatedSignalsWithDuration:0.2 curve:RCLAnimationCurveLinear]
//		/* Animate changes to the alpha, and interrupt for any new animations. */
//		switchToLatest];
//
// Returns a signal of signals, where each inner signal sends one `next`
// that corresponds to a value from the receiver, then completes when the
// animation corresponding to that value has finished. Deferring the events of
// the returned signal or having them delivered on another thread is considered
// undefined behavior.
- (RACSignal *)animatedSignalsWithDuration:(NSTimeInterval)duration curve:(RCLAnimationCurve)curve;

// Behaves like -animateWithDuration: with the system's default animation
// duration.
- (RACSignal *)animate;

// Invokes -animateWithDuration:curve: with a curve of RCLAnimationCurveDefault.
- (RACSignal *)animateWithDuration:(NSTimeInterval)duration;

// Wraps every next in an animation, using the given duration and animation
// curve.
//
// When using this method, new animations will not begin until all previous
// animations have completed. To disable this behavior (on iOS only), use
// -animatedSignalsWithDuration:curve: instead, and flatten or switch the
// returned signal.
//
// Binding the resulting signal to a view property will result in updates to
// that property (that originate from the signal) being automatically animated.
//
// To delay an animation, use -[RACSignal delay:] or -[RACSignal throttle:] on
// the receiver _before_ applying -animate. Because the aforementioned methods
// delay delivery of `next`s, applying them _after_ -animate will cause values
// to be delivered outside of any animation block.
//
// Examples
//
//   RAC(self.textField, rcl_alphaValue, @1) = [[alphaValues
//		/* Animate changes to the alpha without interruption. */
//		animateWithDuration:0.2];
//
//	RAC(self.button, rcl_alphaValue, @1) = [[alphaValues
//		/* Delay animations by 0.1 seconds. */
//		delay:0.1]
//		animateWithDuration:0.2 curve:RCLAnimationCurveLinear];
//
// Returns a signal which animates the sending of its values. Deferring the
// signal's events or having them delivered on another thread is considered
// undefined behavior.
- (RACSignal *)animateWithDuration:(NSTimeInterval)duration curve:(RCLAnimationCurve)curve;

@end
