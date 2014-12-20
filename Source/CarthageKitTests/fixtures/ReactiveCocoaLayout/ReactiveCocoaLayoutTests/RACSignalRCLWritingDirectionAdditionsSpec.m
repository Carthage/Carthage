//
//  RACSignalRCLWritingDirectionAdditionsSpec.m
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-18.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import <Archimedes/Archimedes.h>
#import <Nimble/Nimble.h>
#import <Quick/Quick.h>
#import <ReactiveCocoa/ReactiveCocoa.h>
#import <ReactiveCocoaLayout/ReactiveCocoaLayout.h>

QuickSpecBegin(RACSignalRCLWritingDirectionAdditionsSpec)

it(@"should immediately send the current leading edge", ^{
	__block NSNumber *edge = nil;

	[RACSignal.leadingEdgeSignal subscribeNext:^(NSNumber *x) {
		edge = x;
	}];

	expect(edge).notTo(beNil());
	expect(edge).notTo(equal(@(CGRectMinYEdge)));
	expect(edge).notTo(equal(@(CGRectMaxYEdge)));
});

it(@"should immediately send the current trailing edge", ^{
	__block NSNumber *edge = nil;

	[RACSignal.trailingEdgeSignal subscribeNext:^(NSNumber *x) {
		edge = x;
	}];

	expect(edge).notTo(beNil());
	expect(edge).notTo(equal(@(CGRectMinYEdge)));
	expect(edge).notTo(equal(@(CGRectMaxYEdge)));
});

QuickSpecEnd
