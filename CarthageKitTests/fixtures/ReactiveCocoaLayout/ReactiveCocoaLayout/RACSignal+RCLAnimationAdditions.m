//
//  RACSignal+RCLAnimationAdditions.m
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2013-01-04.
//  Copyright (c) 2013 GitHub. All rights reserved.
//

#import "RACSignal+RCLAnimationAdditions.h"
#import <libkern/OSAtomic.h>
#import <ReactiveCocoa/EXTScope.h>
#import <QuartzCore/QuartzCore.h>

// The number of animated signals in the current chain.
//
// This should only be used while on the main thread.
static NSUInteger RCLSignalAnimationLevel = 0;

BOOL RCLIsInAnimatedSignal (void) {
	if (![NSThread isMainThread]) return NO;

	return RCLSignalAnimationLevel > 0;
}

// Creates a signal of animated signals.
//
// self     - The signal to animate.
// duration - If not nil, an explicit duration to specify when starting the animation.
// curve    - The animation curve to use.
static RACSignal *animatedSignalsWithDuration (RACSignal *self, NSNumber *duration, RCLAnimationCurve curve) {
	#ifdef RCL_FOR_IPHONE
		// `UIViewAnimationOptionLayoutSubviews` seems like a sane default
		// setting for a layout-triggered animation.
		//
		// We use `UIViewAnimationOptionBeginFromCurrentState` to implement
		// interruption behaviors, but ultimately that's controlled by the
		// subscriber (and how the inner signals are combined).
		UIViewAnimationOptions options = curve | UIViewAnimationOptionLayoutSubviews | UIViewAnimationOptionBeginFromCurrentState;
		if (curve != RCLAnimationCurveDefault) options |= UIViewAnimationOptionOverrideInheritedCurve;

		NSTimeInterval durationInterval = (duration != nil ? duration.doubleValue : 0.2);
	#else
		CAMediaTimingFunction *timingFunction;
		switch (curve) {
			case RCLAnimationCurveEaseInOut:
				timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
				break;

			case RCLAnimationCurveEaseIn:
				timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
				break;

			case RCLAnimationCurveEaseOut:
				timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
				break;

			case RCLAnimationCurveLinear:
				timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
				break;

			case RCLAnimationCurveDefault:
				timingFunction = nil;
				break;

			default:
				NSCAssert(NO, @"Unrecognized animation curve: %i", (int)curve);
		}
	#endif

	return [[self map:^(id value) {
		return [[RACSignal createSignal:^ RACDisposable * (id<RACSubscriber> subscriber) {
			++RCLSignalAnimationLevel;
			@onExit {
				NSCAssert(RCLSignalAnimationLevel > 0, @"Unbalanced decrement of RCLSignalAnimationLevel");
				--RCLSignalAnimationLevel;
			};

			#ifdef RCL_FOR_IPHONE
				[UIView animateWithDuration:durationInterval delay:0 options:options animations:^{
					[subscriber sendNext:value];
				} completion:^(BOOL finished) {
					[subscriber sendCompleted];
				}];
			#else
				[NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
					if (duration != nil) context.duration = duration.doubleValue;
					if (timingFunction != nil) context.timingFunction = timingFunction;

					[subscriber sendNext:value];
				} completionHandler:^{
					// Avoids weird AppKit deadlocks when interrupting an
					// existing animation.
					[RACScheduler.mainThreadScheduler schedule:^{
						[subscriber sendCompleted];
					}];
				}];
			#endif

			return nil;
		}] setNameWithFormat:@"[[%@] -animatedSignalsWithDuration: %@ curve: %li] animationSignal: %@", self.name, duration, (long)curve, value];
	}] setNameWithFormat:@"[%@] -animatedSignalsWithDuration: %@ curve: %li", self.name, duration, (long)curve];
}

@implementation RACSignal (RCLAnimationAdditions)

- (RACSignal *)animate {
	return [[animatedSignalsWithDuration(self, nil, RCLAnimationCurveDefault)
		concat]
		setNameWithFormat:@"[%@] -animate", self.name];
}

- (RACSignal *)animateWithDuration:(NSTimeInterval)duration {
	return [self animateWithDuration:duration curve:RCLAnimationCurveDefault];
}

- (RACSignal *)animateWithDuration:(NSTimeInterval)duration curve:(RCLAnimationCurve)curve {
	return [[animatedSignalsWithDuration(self, @(duration), curve)
		concat]
		setNameWithFormat:@"[%@] -animateWithDuration: %@ curve: %li", self.name, @(duration), (long)curve];
}

- (RACSignal *)animatedSignals {
	return animatedSignalsWithDuration(self, nil, RCLAnimationCurveDefault);
}

- (RACSignal *)animatedSignalsWithDuration:(NSTimeInterval)duration {
	return [self animatedSignalsWithDuration:duration curve:RCLAnimationCurveDefault];
}

- (RACSignal *)animatedSignalsWithDuration:(NSTimeInterval)duration curve:(RCLAnimationCurve)curve {
	return animatedSignalsWithDuration(self, @(duration), curve);
}

@end
