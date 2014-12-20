//
//  NSView+RCLGeometryAdditions.m
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-12.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "NSView+RCLGeometryAdditions.h"
#import "RACSignal+RCLAnimationAdditions.h"
#import "View+RCLAutoLayoutAdditions.h"
#import <Archimedes/Archimedes.h>
#import <objc/runtime.h>
#import <ReactiveCocoa/EXTScope.h>
#import <ReactiveCocoa/ReactiveCocoa.h>

@implementation NSView (RCLGeometryAdditions)

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
	if (self.superview != nil && self.window != nil) {
		// Matches the behavior of MEDRectFloor().
		NSAlignmentOptions options = NSAlignMinXOutward | NSAlignMinYInward | NSAlignWidthInward | NSAlignHeightInward;

		CGRect windowFrame = [self.superview convertRect:frame toView:nil];
		CGRect alignedWindowFrame = [self backingAlignedRect:windowFrame options:options];
		frame = [self.superview convertRect:alignedWindowFrame fromView:nil];
	}

	if (RCLIsInAnimatedSignal()) {
		[self.animator setFrame:frame];
	} else {
		self.frame = frame;
	}
}

- (CGRect)rcl_bounds {
	return self.bounds;
}

- (void)setRcl_bounds:(CGRect)bounds {
	if (self.window != nil) {
		// Matches the behavior of MEDRectFloor().
		NSAlignmentOptions options = NSAlignMinXOutward | NSAlignMinYInward | NSAlignWidthInward | NSAlignHeightInward;

		CGRect windowRect = [self convertRect:bounds toView:nil];
		CGRect alignedWindowRect = [self backingAlignedRect:windowRect options:options];
		bounds = [self convertRect:alignedWindowRect fromView:nil];
	}

	if (RCLIsInAnimatedSignal()) {
		[self.animator setBounds:bounds];
	} else {
		self.bounds = bounds;
	}
}

- (CGFloat)rcl_alphaValue {
	return self.alphaValue;
}

- (void)setRcl_alphaValue:(CGFloat)alphaValue {
	if (RCLIsInAnimatedSignal()) {
		[self.animator setAlphaValue:alphaValue];
	} else {
		self.alphaValue = alphaValue;
	}
}

- (BOOL)rcl_isHidden {
	return [self isHidden];
}

- (void)setRcl_hidden:(BOOL)hidden {
	self.hidden = hidden;
}

#pragma mark Signals

- (RACSignal *)rcl_boundsSignal {
	RACSubject *subject = objc_getAssociatedObject(self, _cmd);
	if (subject != nil) return subject;

	subject = [[RACReplaySubject replaySubjectWithCapacity:1] setNameWithFormat:@"%@ -rcl_boundsSignal", self];
	objc_setAssociatedObject(self, _cmd, subject, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	self.postsBoundsChangedNotifications = YES;
	self.postsFrameChangedNotifications = YES;

	RACDisposable *disposable = [[[[[RACSignal
		merge:@[
			[NSNotificationCenter.defaultCenter rac_addObserverForName:NSViewBoundsDidChangeNotification object:self],
			[NSNotificationCenter.defaultCenter rac_addObserverForName:NSViewFrameDidChangeNotification object:self]
		]]
		map:^(NSNotification *notification) {
			NSView *view = notification.object;
			return MEDBox(view.bounds);
		}]
		startWith:MEDBox(self.bounds)]
		distinctUntilChanged]
		subscribe:subject];

	[self.rac_deallocDisposable addDisposable:[RACDisposable disposableWithBlock:^{
		[disposable dispose];
		[subject sendCompleted];
	}]];

	return subject;
}

- (RACSignal *)rcl_frameSignal {
	RACSubject *subject = objc_getAssociatedObject(self, _cmd);
	if (subject != nil) return subject;

	subject = [[RACReplaySubject replaySubjectWithCapacity:1] setNameWithFormat:@"%@ -rcl_frameSignal", self];
	objc_setAssociatedObject(self, _cmd, subject, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	self.postsFrameChangedNotifications = YES;

	RACDisposable *disposable = [[[[[NSNotificationCenter.defaultCenter rac_addObserverForName:NSViewFrameDidChangeNotification object:self]
		map:^(NSNotification *notification) {
			NSView *view = notification.object;
			return MEDBox(view.frame);
		}]
		startWith:MEDBox(self.frame)]
		distinctUntilChanged]
		subscribe:subject];

	[self.rac_deallocDisposable addDisposable:[RACDisposable disposableWithBlock:^{
		[disposable dispose];
		[subject sendCompleted];
	}]];

	return subject;
}

- (RACSignal *)rcl_baselineSignal {
	RACSubject *deallocSubject = [RACReplaySubject replaySubjectWithCapacity:1];
	[self.rac_deallocDisposable addDisposable:[RACDisposable disposableWithBlock:^{
		[deallocSubject sendCompleted];
	}]];

	@unsafeify(self);

	return [[[self.rcl_intrinsicContentSizeSignal
		map:^(id _) {
			@strongify(self);
			return @(self.baselineOffsetFromBottom);
		}]
		takeUntil:deallocSubject]
		setNameWithFormat:@"%@ -rcl_baselineSignal", self];
}

@end
