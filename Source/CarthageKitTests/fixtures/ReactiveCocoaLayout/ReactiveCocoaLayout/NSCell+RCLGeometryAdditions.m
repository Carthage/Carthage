//
//  NSCell+RCLGeometryAdditions.m
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-30.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "NSCell+RCLGeometryAdditions.h"
#import "NSControl+RCLGeometryAdditions.h"
#import <Archimedes/Archimedes.h>
#import <ReactiveCocoa/EXTScope.h>
#import <ReactiveCocoa/ReactiveCocoa.h>

// Returns a signal which sends the given cell once immediately, and then again
// whenever its intrinsic content size is invalidated.
static RACSignal *intrinsicContentSizeInvalidatedSignalForCell(NSCell *self) {
	NSCAssert(self.controlView != nil, @"%@ must have a controlView before its size can be observed", self, __func__);

	NSControl *control = (id)self.controlView;
	NSCAssert([control isKindOfClass:NSControl.class], @"Expected %@ to have an NSControl for its controlView, but got %@", self, control);

	@weakify(self);

	return [[control.rcl_cellIntrinsicContentSizeInvalidatedSignal filter:^(NSCell *cell) {
		@strongify(self);
		return [self isEqual:cell];
	}] startWith:self];
}

@implementation NSCell (RCLGeometryAdditions)

#pragma mark Signals

- (RACSignal *)rcl_sizeSignal {
	return [[intrinsicContentSizeInvalidatedSignalForCell(self) map:^(NSCell *cell) {
		return MEDBox(cell.cellSize);
	}] setNameWithFormat:@"%@ -rcl_sizeSignal", self];
}

- (RACSignal *)rcl_sizeSignalForBounds:(RACSignal *)boundsSignal {
	NSParameterAssert(boundsSignal != nil);

	return [[RACSignal combineLatest:@[ boundsSignal, intrinsicContentSizeInvalidatedSignalForCell(self) ] reduce:^(NSValue *value, NSCell *cell) {
		NSAssert([value isKindOfClass:NSValue.class] && value.med_geometryStructType == MEDGeometryStructTypeRect, @"Value sent by %@ is not a CGRect: %@", boundsSignal, value);

		return MEDBox([cell cellSizeForBounds:value.med_rectValue]);
	}] setNameWithFormat:@"%@ -rcl_sizeSignalForBounds: %@", self, boundsSignal];
}

@end
