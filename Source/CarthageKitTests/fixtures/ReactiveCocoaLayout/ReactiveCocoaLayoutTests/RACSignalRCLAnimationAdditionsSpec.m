//
//  RACSignalRCLAnimationAdditionsSpec.m
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2013-01-04.
//  Copyright (c) 2013 GitHub. All rights reserved.
//

#import <Archimedes/Archimedes.h>
#import <Nimble/Nimble.h>
#import <Quick/Quick.h>
#import <ReactiveCocoa/ReactiveCocoa.h>
#import <ReactiveCocoaLayout/ReactiveCocoaLayout.h>

QuickSpecBegin(RACSignalRCLAnimationAdditions)

__block RACSignal *baseSignal;

beforeEach(^{
	baseSignal = [@[ @0, @1, @2 ].rac_sequence signalWithScheduler:RACScheduler.immediateScheduler];
});

describe(@"-animatedSignalsWithDuration:curve:", ^{
	it(@"should send a signal for each next", ^{
		__block NSUInteger signalsReceived = 0;

		[[baseSignal
			animatedSignalsWithDuration:0.01 curve:RCLAnimationCurveEaseOut]
			subscribeNext:^(RACSignal *signal) {
				expect([signal first]).to(equal(@(signalsReceived)));
				signalsReceived++;
			}];

		expect(@(signalsReceived)).toEventually(equal(@3));
	});

	it(@"should send the underlying value immediately, then complete later", ^{
		__block NSUInteger signalsReceived = 0;
		__block NSUInteger signalsCompleted = 0;

		[[baseSignal
			animatedSignalsWithDuration:0.01]
			subscribeNext:^(RACSignal *signal) {
				__block id value = nil;
				[signal subscribeNext:^(id x) {
					expect(value).to(beNil());
					expect(x).notTo(beNil());

					value = x;
				} completed:^{
					signalsCompleted++;
				}];

				// The underlying value should have been sent synchronously.
				expect(value).to(equal(@(signalsReceived)));
				signalsReceived++;
			}];

		expect(@(signalsReceived)).toEventually(equal(@3));
		expect(@(signalsCompleted)).toEventually(equal(@3));
	});

	it(@"should start animating only when subscribed to", ^{
		__block NSUInteger signalsStarted = 0;
		__block NSUInteger valuesReceived = 0;

		[[[[baseSignal
			animatedSignals]
			map:^(RACSignal *signal) {
				return [signal initially:^{
					signalsStarted++;
				}];
			}]
			concat]
			subscribeNext:^(id _) {
				valuesReceived++;
				expect(@(valuesReceived)).to(equal(@(signalsStarted)));
			}];

		expect(@(valuesReceived)).toEventually(equal(@3));
	});
});

describe(@"RCLIsInAnimatedSignal()", ^{
	it(@"should be false outside of an animated signal", ^{
		expect(@(RCLIsInAnimatedSignal())).to(beFalsy());
	});

	it(@"should be true from nexts of -animate", ^{
		[[[[[baseSignal
			take:1]
			animate]
			doNext:^(id x) {
				expect(x).to(equal(@0));
				expect(@(RCLIsInAnimatedSignal())).to(beTruthy());
			}]
			doCompleted:^{
				expect(@(RCLIsInAnimatedSignal())).to(beFalsy());
			}]
			asynchronouslyWaitUntilCompleted:NULL];
	});

	it(@"should be true from nexts of -animateWithDuration:", ^{
		[[[[[baseSignal
			take:1]
			animateWithDuration:0.01]
			doNext:^(id x) {
				expect(x).to(equal(@0));
				expect(@(RCLIsInAnimatedSignal())).to(beTruthy());
			}]
			doCompleted:^{
				expect(@(RCLIsInAnimatedSignal())).to(beFalsy());
			}]
			asynchronouslyWaitUntilCompleted:NULL];
	});

	it(@"should be true from nexts of -animateWithDuration:curve:", ^{
		[[[[[baseSignal
			take:1]
			animateWithDuration:0.01 curve:RCLAnimationCurveEaseOut]
			doNext:^(id x) {
				expect(x).to(equal(@0));
				expect(@(RCLIsInAnimatedSignal())).to(beTruthy());
			}]
			doCompleted:^{
				expect(@(RCLIsInAnimatedSignal())).to(beFalsy());
			}]
			asynchronouslyWaitUntilCompleted:NULL];
	});

	it(@"should be false from nexts of -animatedSignals", ^{
		[[[[baseSignal
			take:1]
			animatedSignalsWithDuration:0.01]
			doNext:^(RACSignal *signal) {
				expect(@(RCLIsInAnimatedSignal())).to(beFalsy());
			}]
			asynchronouslyWaitUntilCompleted:NULL];
	});

	it(@"should be true from nexts of inner signals from -animatedSignals", ^{
		[[[[[[baseSignal
			take:1]
			animatedSignalsWithDuration:0.01]
			concat]
			doNext:^(id x) {
				expect(x).to(equal(@0));
				expect(@(RCLIsInAnimatedSignal())).to(beTruthy());
			}]
			doCompleted:^{
				expect(@(RCLIsInAnimatedSignal())).to(beFalsy());
			}]
			asynchronouslyWaitUntilCompleted:NULL];
	});
});

QuickSpecEnd
