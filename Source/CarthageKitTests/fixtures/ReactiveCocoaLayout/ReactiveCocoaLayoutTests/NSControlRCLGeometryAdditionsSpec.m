//
//  NSControlRCLGeometryAdditionsSpec.m
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-30.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import <Archimedes/Archimedes.h>
#import <Nimble/Nimble.h>
#import <Quick/Quick.h>
#import <ReactiveCocoa/ReactiveCocoa.h>
#import <ReactiveCocoaLayout/ReactiveCocoaLayout.h>

QuickSpecBegin(NSControlRCLGeometryAdditions)

describe(@"NSTextField", ^{
	__block NSTextField *field;

	beforeEach(^{
		field = [[NSTextField alloc] initWithFrame:CGRectMake(0, 0, 100, 20)];
		expect(field).notTo(beNil());
	});

	it(@"should send the adjusted NSCell whenever the intrinsic content size changes", ^{
		__block NSCell *invalidatedCell = nil;
		[field.rcl_cellIntrinsicContentSizeInvalidatedSignal subscribeNext:^(NSCell *cell) {
			expect(cell).to(beAKindOf(NSTextFieldCell.class));
			invalidatedCell = cell;
		}];

		[field.cell setStringValue:@"foo\nbar"];
		expect(invalidatedCell).to(equal(field.cell));
	});
});

describe(@"NSMatrix", ^{
	__block NSMatrix *matrix;
	__block NSCell *cell;

	beforeEach(^{
		matrix = [[NSMatrix alloc] initWithFrame:CGRectZero mode:NSListModeMatrix cellClass:NSTextFieldCell.class numberOfRows:2 numberOfColumns:2];
		expect(matrix).notTo(beNil());

		cell = matrix.cells[0];

		// This is apparently necessary for the controlView property to be
		// filled in.
		[matrix calcSize];

		expect(cell.controlView).to(equal(matrix));
	});

	it(@"should send the adjusted NSCell whenever the intrinsic content size changes", ^{
		NSMutableSet *invalidatedCells = [NSMutableSet set];
		[matrix.rcl_cellIntrinsicContentSizeInvalidatedSignal subscribeNext:^(NSCell *cell) {
			expect(cell).to(beAKindOf(NSTextFieldCell.class));
			[invalidatedCells addObject:cell];
		}];

		cell.stringValue = @"foo\nbar";
		expect(invalidatedCells).to(contain(cell));
	});
});

it(@"should complete rcl_cellIntrinsicContentSizeInvalidatedSignal upon deallocation", ^{
	__block BOOL completed = NO;

	@autoreleasepool {
		NSControl *control __attribute__((objc_precise_lifetime)) = [[NSControl alloc] initWithFrame:NSZeroRect];
		[control.rcl_cellIntrinsicContentSizeInvalidatedSignal subscribeCompleted:^{
			completed = YES;
		}];

		expect(@(completed)).to(beFalsy());
	}

	expect(@(completed)).to(beTruthy());
});

QuickSpecEnd
