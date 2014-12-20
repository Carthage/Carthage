//
//  View+RCLAutoLayoutAdditions.m
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-17.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "View+RCLAutoLayoutAdditions.h"
#import "RACSignal+RCLGeometryAdditions.h"
#import <Archimedes/Archimedes.h>
#import <objc/runtime.h>
#import <ReactiveCocoa/EXTScope.h>
#import <ReactiveCocoa/ReactiveCocoa.h>

#ifdef RCL_FOR_IPHONE
#import "UIView+RCLGeometryAdditions.h"
#else
#import "NSView+RCLGeometryAdditions.h"
#endif

// Associated with a RACSubject which sends -intrinsicContentSize whenever
// -invalidateIntrinsicContentSize is invoked.
static void *IntrinsicContentSizeSubjectKey = &IntrinsicContentSizeSubjectKey;

static void (*oldInvalidateIntrinsicContentSize)(id, SEL);
static void newInvalidateIntrinsicContentSize(id self, SEL _cmd) {
	oldInvalidateIntrinsicContentSize(self, _cmd);

	RACSubject *subject = objc_getAssociatedObject(self, IntrinsicContentSizeSubjectKey);
	if (subject == nil) return;

	[subject sendNext:MEDBox([self intrinsicContentSize])];
}

#ifdef RCL_FOR_IPHONE
@implementation UIView (RCLAutoLayoutAdditions)
#else
@implementation NSView (RCLAutoLayoutAdditions)
#endif

#pragma mark Lifecycle

+ (void)load {
	SEL selector = @selector(invalidateIntrinsicContentSize);

	Method method = class_getInstanceMethod(self, selector);
	NSAssert(method != NULL, @"Could not find %@ on %@", NSStringFromSelector(selector), self);

	oldInvalidateIntrinsicContentSize = (__typeof__(oldInvalidateIntrinsicContentSize))method_getImplementation(method);
	class_replaceMethod(self, selector, (IMP)&newInvalidateIntrinsicContentSize, method_getTypeEncoding(method));
}

#pragma mark Signals

- (RACSignal *)rcl_intrinsicContentSizeSignal {
	RACSubject *subject = objc_getAssociatedObject(self, IntrinsicContentSizeSubjectKey);
	if (subject == nil) {
		subject = [RACReplaySubject replaySubjectWithCapacity:1];
		[subject sendNext:MEDBox(self.intrinsicContentSize)];

		objc_setAssociatedObject(self, IntrinsicContentSizeSubjectKey, subject, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		[self.rac_deallocDisposable addDisposable:[RACDisposable disposableWithBlock:^{
			[subject sendCompleted];
		}]];
	}

	return [[subject distinctUntilChanged] setNameWithFormat:@"%@ -rcl_intrinsicContentSizeSignal", self];
}

- (RACSignal *)rcl_intrinsicBoundsSignal {
	return [[RACSignal rectsWithSize:self.rcl_intrinsicContentSizeSignal] setNameWithFormat:@"%@ -rcl_intrinsicBoundsSignal", self];
}

- (RACSignal *)rcl_intrinsicHeightSignal {
	return [self.rcl_intrinsicContentSizeSignal.height setNameWithFormat:@"%@ -rcl_intrinsicHeightSignal", self];
}

- (RACSignal *)rcl_intrinsicWidthSignal {
	return [self.rcl_intrinsicContentSizeSignal.width setNameWithFormat:@"%@ -rcl_intrinsicWidthSignal", self];
}

- (RACSignal *)rcl_alignmentRectSignal {
	@unsafeify(self);

	return [[[self.rcl_frameSignal
		map:^(id _) {
			@strongify(self);
			return MEDBox(self.rcl_alignmentRect);
		}]
		distinctUntilChanged]
		setNameWithFormat:@"%@ -rcl_alignmentRectSignal", self];
}

@end
