//
//  UIViewRCLGeometryAdditionsSpec.m
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-15.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import <Archimedes/Archimedes.h>
#import <Nimble/Nimble.h>
#import <Quick/Quick.h>
#import <ReactiveCocoa/ReactiveCocoa.h>
#import <ReactiveCocoaLayout/ReactiveCocoaLayout.h>

#import "ViewExamples.h"

QuickSpecBegin(UIViewRCLGeometryAdditions)

itBehavesLike(ViewExamples, nil);

describe(@"UILabel", ^{
	__block UILabel *label;

	beforeEach(^{
		label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 100, 20)];
		expect(label).notTo(beNil());
	});

	describe(@"baseline", ^{
		__block CGFloat baseline;

		beforeEach(^{
			UIView *baselineView = label.viewForBaselineLayout;
			expect(baselineView).to(equal(label));

			baseline = 0;
		});

		it(@"should send the baseline", ^{
			expect([label.rcl_baselineSignal first]).to(equal(@(baseline)));
		});
	});
});

QuickSpecEnd
