//
//  NSControl+RCLGeometryAdditions.m
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-30.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "NSControl+RCLGeometryAdditions.h"
#import <objc/runtime.h>
#import <ReactiveCocoa/ReactiveCocoa.h>

// Associated with a RACSubject which sends whenever
// -invalidateIntrinsicContentSizeForCell: is invoked.
static void *IntrinsicContentSizeSubjectKey = &IntrinsicContentSizeSubjectKey;

static void (*oldInvalidateIntrinsicContentSizeForCell)(id, SEL, id);
static void newInvalidateIntrinsicContentSizeForCell(NSControl *self, SEL _cmd, NSCell *cell) {
	oldInvalidateIntrinsicContentSizeForCell(self, _cmd, cell);

	RACSubject *subject = objc_getAssociatedObject(self, IntrinsicContentSizeSubjectKey);
	if (subject == nil) return;

	[subject sendNext:cell];
}

@implementation NSControl (RCLGeometryAdditions)

#pragma mark Lifecycle

+ (void)load {
	SEL selector = @selector(invalidateIntrinsicContentSizeForCell:);

	Method method = class_getInstanceMethod(self, selector);
	NSAssert(method != NULL, @"Could not find %@ on %@", NSStringFromSelector(selector), self);

	oldInvalidateIntrinsicContentSizeForCell = (__typeof__(oldInvalidateIntrinsicContentSizeForCell))method_getImplementation(method);
	class_replaceMethod(self, selector, (IMP)&newInvalidateIntrinsicContentSizeForCell, method_getTypeEncoding(method));
}

#pragma mark Signals

- (RACSignal *)rcl_cellIntrinsicContentSizeInvalidatedSignal {
	RACSubject *subject = objc_getAssociatedObject(self, IntrinsicContentSizeSubjectKey);
	if (subject == nil) {
		subject = [RACSubject subject];
		[subject setNameWithFormat:@"%@ -rcl_cellIntrinsicContentSizeInvalidatedSignal", self];

		objc_setAssociatedObject(self, IntrinsicContentSizeSubjectKey, subject, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		[self.rac_deallocDisposable addDisposable:[RACDisposable disposableWithBlock:^{
			[subject sendCompleted];
		}]];
	}

	return subject;
}

@end
