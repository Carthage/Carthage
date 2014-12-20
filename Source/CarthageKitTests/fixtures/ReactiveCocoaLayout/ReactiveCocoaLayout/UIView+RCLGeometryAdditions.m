//
//  UIView+RCLGeometryAdditions.m
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-13.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "UIView+RCLGeometryAdditions.h"
#import "RACSignal+RCLGeometryAdditions.h"
#import <Archimedes/Archimedes.h>
#import <ReactiveCocoa/EXTScope.h>
#import <ReactiveCocoa/ReactiveCocoa.h>

// Aligns the given rectangle to the pixels on the view's screen, or the main
// screen if the view is not attached to a screen yet.
static CGRect backingAlignedRect(UIView *view, CGRect rect) {
	NSCParameterAssert(view != nil);

	UIScreen *screen = view.window.screen ?: UIScreen.mainScreen;
	NSCAssert(screen != nil, @"Could not find a screen for view %@", view);
	NSCAssert(screen.scale > 0, @"Screen has a weird scale: %@", screen);

	rect.origin.x *= screen.scale;
	rect.origin.y *= screen.scale;
	rect.size.width *= screen.scale;
	rect.size.height *= screen.scale;

	rect = MEDRectFloor(rect);

	rect.origin.x /= screen.scale;
	rect.origin.y /= screen.scale;
	rect.size.width /= screen.scale;
	rect.size.height /= screen.scale;

	return rect;
}

@implementation UIView (RCLGeometryAdditions)

#pragma mark Properties

- (CGRect)rcl_alignmentRect {
	return [self alignmentRectForFrame:self.frame];
}

- (void)setRcl_alignmentRect:(CGRect)rect {
	self.rcl_frame = [self frameForAlignmentRect:rect];
}

- (CGRect)rcl_frame {
	return self.frame;
}

- (void)setRcl_frame:(CGRect)frame {
	self.frame = backingAlignedRect(self, frame);
}

- (CGRect)rcl_bounds {
	return self.bounds;
}

- (void)setRcl_bounds:(CGRect)bounds {
	self.bounds = backingAlignedRect(self, bounds);
}

#pragma mark Signals

// FIXME: These properties aren't actually declared as KVO-compliant by Core
// Animation. Here be dragons?
- (RACSignal *)rcl_boundsSignal {
	@weakify(self);

	return [[[RACObserve(self, layer.bounds)
		map:^(id _) {
			@strongify(self);
			return MEDBox(self.bounds);
		}]
		distinctUntilChanged]
		setNameWithFormat:@"%@ -rcl_boundsSignal", self];
}

- (RACSignal *)rcl_frameSignal {
	@weakify(self);

	return [[[[RACSignal
		merge:@[ self.rcl_boundsSignal, RACObserve(self, layer.position) ]]
		map:^(id _) {
			@strongify(self);
			return MEDBox(self.frame);
		}]
		distinctUntilChanged]
		setNameWithFormat:@"%@ -rcl_frameSignal", self];
}

- (RACSignal *)rcl_baselineSignal {
	RACSignal *signal;

	if (self.viewForBaselineLayout == self) {
		// The baseline will always be the bottom of our bounds.
		signal = [RACSignal return:@0];
	} else {
		@weakify(self);
		signal = [[RACSignal
			merge:@[ self.rcl_boundsSignal, self.rcl_frameSignal, self.viewForBaselineLayout.rcl_frameSignal ]]
			map:^(id _) {
				@strongify(self);

				UIView *baselineView = self.viewForBaselineLayout;
				NSAssert([baselineView.superview isEqual:self], @"%@ must be a subview of %@ to be its viewForBaselineLayout", baselineView, self);

				return @(CGRectGetHeight(self.bounds) - CGRectGetMaxY(baselineView.frame));
			}].distinctUntilChanged;
	}

	return [signal setNameWithFormat:@"%@ -rcl_baselineSignal", self];
}

@end
