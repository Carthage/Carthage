//
//  RCLMacrosSpec.m
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2013-05-11.
//  Copyright (c) 2013 GitHub. All rights reserved.
//

#import <Archimedes/Archimedes.h>
#import <Nimble/Nimble.h>
#import <Quick/Quick.h>
#import <ReactiveCocoa/ReactiveCocoa.h>
#import <ReactiveCocoaLayout/ReactiveCocoaLayout.h>

#import "TestView.h"

static NSString * const MacroBindingExamples = @"MacroBindingExamples";

// Associated with a block that binds a dictionary of attributes to the desired
// view property. This block should be of type:
//
// void (^bind)(TestView *view, NSDictionary *attributes)
static NSString * const MacroBindingBlock = @"MacroBindingBlock";

// Associated with the name of the view property that is being bound.
static NSString * const MacroPropertyName = @"MacroPropertyName";

QuickConfigurationBegin(MacroBindingExampleGroup)

+ (void)configure:(Configuration *)configuration {
	sharedExamples(MacroBindingExamples, ^(QCKDSLSharedExampleContext data) {
		CGSize intrinsicSize = CGSizeMake(10, 15);

		__block TestView *view;

		__block void (^bind)(NSDictionary *);
		__block NSValue * (^getProperty)(void);

		__block CGRect rect;
		__block RACSubject *values;

		beforeEach(^{
			view = [[TestView alloc] initWithFrame:CGRectZero];
			[view invalidateAndSetIntrinsicContentSize:intrinsicSize];

			void (^innerBindingBlock)(TestView *, NSDictionary *) = data()[MacroBindingBlock];
			bind = [^(NSDictionary *bindings) {
				return innerBindingBlock(view, bindings);
			} copy];

			getProperty = [^{
				return [view valueForKey:data()[MacroPropertyName]];
			} copy];

			rect = CGRectMake(0, 0, intrinsicSize.width, intrinsicSize.height);
			values = [RACSubject subject];
		});

		it(@"should default to the view's intrinsic bounds", ^{
			bind(@{});

			CGRect rect = { .origin = CGPointZero, .size = intrinsicSize };
			expect(getProperty()).to(equal(MEDBox(rect)));
		});

		describe(@"rcl_rect", ^{
			beforeEach(^{
				rect = CGRectMake(1, 7, 13, 21);
			});

			it(@"should bind to a constant", ^{
				bind(@{
					rcl_rect: MEDBox(rect)
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should bind to a signal", ^{
				bind(@{
					rcl_rect: values
				});

				[values sendNext:MEDBox(rect)];
				expect(getProperty()).to(equal(MEDBox(rect)));

				rect = CGRectMake(2, 3, 4, 5);

				[values sendNext:MEDBox(rect)];
				expect(getProperty()).to(equal(MEDBox(rect)));
			});
		});

		describe(@"rcl_size", ^{
			beforeEach(^{
				rect.size = CGSizeMake(13, 21);
			});

			it(@"should bind to a constant", ^{
				bind(@{
					rcl_size: MEDBox(rect.size)
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should bind to a signal", ^{
				bind(@{
					rcl_size: values
				});

				[values sendNext:MEDBox(rect.size)];
				expect(getProperty()).to(equal(MEDBox(rect)));

				rect.size = CGSizeMake(4, 5);

				[values sendNext:MEDBox(rect.size)];
				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should override rcl_rect", ^{
				CGRect clobberRect = { .origin = rect.origin, .size = CGSizeMake(100, 500) };

				bind(@{
					rcl_rect: MEDBox(clobberRect),
					rcl_size: MEDBox(rect.size)
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});
		});

		describe(@"rcl_origin", ^{
			beforeEach(^{
				rect = CGRectMake(1, 3, intrinsicSize.width, intrinsicSize.height);
			});

			it(@"should bind to a constant", ^{
				bind(@{
					rcl_origin: MEDBox(rect.origin)
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should bind to a signal", ^{
				bind(@{
					rcl_origin: values
				});

				[values sendNext:MEDBox(rect.origin)];
				expect(getProperty()).to(equal(MEDBox(rect)));

				rect.origin = CGPointMake(5, 7);

				[values sendNext:MEDBox(rect.origin)];
				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should override rcl_rect", ^{
				CGRect clobberRect = { .origin = CGPointMake(100, 500), .size = rect.size };

				bind(@{
					rcl_rect: MEDBox(clobberRect),
					rcl_origin: MEDBox(rect.origin)
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});
		});

		describe(@"rcl_width", ^{
			beforeEach(^{
				rect.size.width = 3;
			});

			it(@"should bind to a constant", ^{
				bind(@{
					rcl_width: @(rect.size.width)
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should bind to a signal", ^{
				bind(@{
					rcl_width: values
				});

				[values sendNext:@(rect.size.width)];
				expect(getProperty()).to(equal(MEDBox(rect)));

				rect.size.width = 7;

				[values sendNext:@(rect.size.width)];
				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should override rcl_size", ^{
				CGSize clobberSize = { .width = 999, .height = rect.size.height };

				bind(@{
					rcl_size: MEDBox(clobberSize),
					rcl_width: @(rect.size.width)
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});
		});

		describe(@"rcl_height", ^{
			beforeEach(^{
				rect.size.height = 3;
			});

			it(@"should bind to a constant", ^{
				bind(@{
					rcl_height: @(rect.size.height)
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should bind to a signal", ^{
				bind(@{
					rcl_height: values
				});

				[values sendNext:@(rect.size.height)];
				expect(getProperty()).to(equal(MEDBox(rect)));

				rect.size.height = 7;

				[values sendNext:@(rect.size.height)];
				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should override rcl_size", ^{
				CGSize clobberSize = { .width = rect.size.width, .height = 999 };

				bind(@{
					rcl_size: MEDBox(clobberSize),
					rcl_height: @(rect.size.height)
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});
		});

		describe(@"rcl_center", ^{
			__block NSValue * (^getCenter)(void);

			beforeEach(^{
				rect.origin = CGPointMake(2, 3);
				getCenter = ^{
					return MEDBox(CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect)));
				};
			});

			it(@"should bind to a constant", ^{
				bind(@{
					rcl_center: getCenter()
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should bind to a signal", ^{
				bind(@{
					rcl_center: values
				});

				[values sendNext:getCenter()];
				expect(getProperty()).to(equal(MEDBox(rect)));

				rect.origin = CGPointMake(4, 5);

				[values sendNext:getCenter()];
				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should override rcl_origin", ^{
				CGPoint clobberOrigin = CGPointMake(999, 333);

				bind(@{
					rcl_origin: MEDBox(clobberOrigin),
					rcl_center: getCenter()
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});
		});

		describe(@"rcl_centerX", ^{
			__block NSNumber * (^getCenter)(void);

			beforeEach(^{
				rect.origin.x = 2;
				getCenter = ^{
					return @(CGRectGetMidX(rect));
				};
			});

			it(@"should bind to a constant", ^{
				bind(@{
					rcl_centerX: getCenter()
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should bind to a signal", ^{
				bind(@{
					rcl_centerX: values
				});

				[values sendNext:getCenter()];
				expect(getProperty()).to(equal(MEDBox(rect)));

				rect.origin.x = 4;

				[values sendNext:getCenter()];
				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should override rcl_center", ^{
				CGPoint clobberCenter = CGPointMake(999, CGRectGetMidY(rect));

				bind(@{
					rcl_center: MEDBox(clobberCenter),
					rcl_centerX: getCenter()
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});
		});

		describe(@"rcl_centerY", ^{
			__block NSNumber * (^getCenter)(void);

			beforeEach(^{
				rect.origin.y = 2;
				getCenter = ^{
					return @(CGRectGetMidY(rect));
				};
			});

			it(@"should bind to a constant", ^{
				bind(@{
					rcl_centerY: getCenter()
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should bind to a signal", ^{
				bind(@{
					rcl_centerY: values
				});

				[values sendNext:getCenter()];
				expect(getProperty()).to(equal(MEDBox(rect)));

				rect.origin.y = 4;

				[values sendNext:getCenter()];
				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should override rcl_origin", ^{
				CGPoint clobberCenter = CGPointMake(CGRectGetMidX(rect), 999);

				bind(@{
					rcl_center: MEDBox(clobberCenter),
					rcl_centerY: getCenter()
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});
		});

		describe(@"rcl_left", ^{
			beforeEach(^{
				rect.origin.x = 7;
			});

			it(@"should bind to a constant", ^{
				bind(@{
					rcl_left: @(rect.origin.x)
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should bind to a signal", ^{
				bind(@{
					rcl_left: values
				});

				[values sendNext:@(rect.origin.x)];
				expect(getProperty()).to(equal(MEDBox(rect)));

				rect.origin.x = 17;

				[values sendNext:@(rect.origin.x)];
				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should override rcl_centerX", ^{
				bind(@{
					rcl_centerX: @999,
					rcl_left: @(rect.origin.x)
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});
		});

		describe(@"rcl_right", ^{
			__block NSNumber * (^getRight)(void);

			beforeEach(^{
				rect.origin.x = 7;
				getRight = ^{
					return @(CGRectGetMaxX(rect));
				};
			});

			it(@"should bind to a constant", ^{
				bind(@{
					rcl_right: getRight()
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should bind to a signal", ^{
				bind(@{
					rcl_right: values
				});

				[values sendNext:getRight()];
				expect(getProperty()).to(equal(MEDBox(rect)));

				rect.origin.x = 17;

				[values sendNext:getRight()];
				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should override rcl_centerX", ^{
				bind(@{
					rcl_centerX: @999,
					rcl_right: getRight()
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});
		});

		describe(@"rcl_top", ^{
			__block NSNumber * (^getTop)(void);

			beforeEach(^{
				rect.origin.y = 7;
				getTop = ^{
					#ifdef RCL_FOR_IPHONE
						return @(CGRectGetMinY(rect));
					#else
						return @(CGRectGetMaxY(rect));
					#endif
				};
			});

			it(@"should bind to a constant", ^{
				bind(@{
					rcl_top: getTop()
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should bind to a signal", ^{
				bind(@{
					rcl_top: values
				});

				[values sendNext:getTop()];
				expect(getProperty()).to(equal(MEDBox(rect)));

				rect.origin.y = 17;

				[values sendNext:getTop()];
				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should override rcl_centerY", ^{
				bind(@{
					rcl_centerY: @999,
					rcl_top: getTop()
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});
		});

		describe(@"rcl_bottom", ^{
			__block NSNumber * (^getBottom)(void);

			beforeEach(^{
				rect.origin.y = 7;
				getBottom = ^{
					#ifdef RCL_FOR_IPHONE
						return @(CGRectGetMaxY(rect));
					#else
						return @(CGRectGetMinY(rect));
					#endif
				};
			});

			it(@"should bind to a constant", ^{
				bind(@{
					rcl_bottom: getBottom()
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should bind to a signal", ^{
				bind(@{
					rcl_bottom: values
				});

				[values sendNext:getBottom()];
				expect(getProperty()).to(equal(MEDBox(rect)));

				rect.origin.y = 17;

				[values sendNext:getBottom()];
				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should override rcl_centerY", ^{
				bind(@{
					rcl_centerY: @999,
					rcl_bottom: getBottom()
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});
		});

		describe(@"rcl_leading", ^{
			__block NSNumber * (^getLeading)(void);

			beforeEach(^{
				rect.origin.x = 7;
				getLeading = ^{
					NSNumber *edge = [[RACSignal leadingEdgeSignal] first];
					if (edge.integerValue == CGRectMinXEdge) {
						return @(CGRectGetMinX(rect));
					} else {
						return @(CGRectGetMaxX(rect));
					}
				};
			});

			it(@"should bind to a constant", ^{
				bind(@{
					rcl_leading: getLeading()
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should bind to a signal", ^{
				bind(@{
					rcl_leading: values
				});

				[values sendNext:getLeading()];
				expect(getProperty()).to(equal(MEDBox(rect)));

				rect.origin.x = 17;

				[values sendNext:getLeading()];
				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should override rcl_centerX", ^{
				bind(@{
					rcl_centerX: @999,
					rcl_leading: getLeading()
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});
		});

		describe(@"rcl_trailing", ^{
			__block NSNumber * (^getTrailing)(void);

			beforeEach(^{
				rect.origin.x = 7;
				getTrailing = ^{
					NSNumber *edge = [[RACSignal trailingEdgeSignal] first];
					if (edge.integerValue == CGRectMinXEdge) {
						return @(CGRectGetMinX(rect));
					} else {
						return @(CGRectGetMaxX(rect));
					}
				};
			});

			it(@"should bind to a constant", ^{
				bind(@{
					rcl_trailing: getTrailing()
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should bind to a signal", ^{
				bind(@{
					rcl_trailing: values
				});

				[values sendNext:getTrailing()];
				expect(getProperty()).to(equal(MEDBox(rect)));

				rect.origin.x = 17;

				[values sendNext:getTrailing()];
				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should override rcl_centerX", ^{
				bind(@{
					rcl_centerX: @999,
					rcl_trailing: getTrailing()
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});
		});

		describe(@"combining non-conflicting attributes", ^{
			it(@"should combine rcl_origin with rcl_width and rcl_height", ^{
				rect = CGRectMake(7, 13, 29, 39);

				bind(@{
					rcl_origin: MEDBox(rect.origin),
					rcl_width: @(rect.size.width),
					rcl_height: @(rect.size.height),
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should combine rcl_size with rcl_center", ^{
				CGPoint center = CGPointMake(2, 5);
				rect = CGRectMake(0, 1, 4, 8);

				bind(@{
					rcl_size: MEDBox(rect.size),
					rcl_center: MEDBox(center),
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});

			it(@"should combine rcl_left, rcl_centerY, rcl_width, and rcl_height", ^{
				CGFloat centerY = 5;
				rect = CGRectMake(0, 1, 4, 8);

				bind(@{
					rcl_left: @(rect.origin.x),
					rcl_centerY: @(centerY),
					rcl_width: @(rect.size.width),
					rcl_height: @(rect.size.height),
				});

				expect(getProperty()).to(equal(MEDBox(rect)));
			});
		});
	});
}

QuickConfigurationEnd

QuickSpecBegin(RCLMacros)

describe(@"RCLFrame", ^{
	itBehavesLike(MacroBindingExamples, ^{
		return @{
			MacroPropertyName: @"rcl_frame",
			MacroBindingBlock: ^(TestView *view, NSDictionary *bindings) {
				RCLFrame(view) = bindings;
			}
		};
	});
});

describe(@"RCLAlignment", ^{
	itBehavesLike(MacroBindingExamples, ^{
		return @{
			MacroPropertyName: @"rcl_alignmentRect",
			MacroBindingBlock: ^(TestView *view, NSDictionary *bindings) {
				RCLAlignment(view) = bindings;
			}
		};
	});

	describe(@"rcl_baseline", ^{
		__block TestView *view;
		__block TestView *alignmentView5;
		__block TestView *alignmentView10;

		__block CGRect rectAligned5;
		__block CGRect rectAligned10;

		__block RACSubject *values;

		beforeEach(^{
			CGRect frame = CGRectMake(0, 0, 20, 20);

			view = [[TestView alloc] initWithFrame:frame];
			[view invalidateAndSetIntrinsicContentSize:frame.size];

			values = [RACSubject subject];

			alignmentView5 = [[TestView alloc] initWithFrame:frame];
			alignmentView5.baselineOffsetFromBottom = 5;
			expect([alignmentView5.rcl_baselineSignal first]).to(equal(@5));

			alignmentView10 = [[TestView alloc] initWithFrame:frame];
			alignmentView10.baselineOffsetFromBottom = 10;
			expect([alignmentView10.rcl_baselineSignal first]).to(equal(@10));

			rectAligned5 = frame;
			rectAligned10 = frame;

			// Gotta take alignment rect padding into account here.
			#ifdef RCL_FOR_IPHONE
			rectAligned5.origin.y = -7;
			rectAligned10.origin.y = -12;
			#else
			rectAligned5.origin.y = 7;
			rectAligned10.origin.y = 12;
			#endif
		});

		it(@"should bind to a constant", ^{
			RCLAlignment(view) = @{
				rcl_baseline: alignmentView5
			};

			expect(MEDBox(view.rcl_alignmentRect)).to(equal(MEDBox(rectAligned5)));
		});

		it(@"should bind to a signal", ^{
			RCLAlignment(view) = @{
				rcl_baseline: values
			};

			[values sendNext:alignmentView5];
			expect(MEDBox(view.rcl_alignmentRect)).to(equal(MEDBox(rectAligned5)));

			[values sendNext:alignmentView10];
			expect(MEDBox(view.rcl_alignmentRect)).to(equal(MEDBox(rectAligned10)));
		});

		it(@"should override rcl_top", ^{
			RCLAlignment(view) = @{
				rcl_top: @999,
				rcl_baseline: alignmentView5
			};

			expect(MEDBox(view.rcl_alignmentRect)).to(equal(MEDBox(rectAligned5)));
		});
	});
});

describe(@"RCLBox", ^{
	it(@"should create a constant signal of int", ^{
		RACSignal *signal = RCLBox(INT_MIN);
		expect([signal toArray]).to(equal(@[ @(INT_MIN) ]));
	});

	it(@"should create a constant signal of unsigned int", ^{
		RACSignal *signal = RCLBox(UINT_MAX);
		expect([signal toArray]).to(equal(@[ @(UINT_MAX) ]));
	});

	it(@"should create a constant signal of long long", ^{
		RACSignal *signal = RCLBox(LLONG_MIN);
		expect([signal toArray]).to(equal(@[ @(LLONG_MIN) ]));
	});

	it(@"should create a constant signal of unsigned long long", ^{
		RACSignal *signal = RCLBox(ULLONG_MAX);
		expect([signal toArray]).to(equal(@[ @(ULLONG_MAX) ]));
	});

	it(@"should create a constant signal of signed char", ^{
		signed char value = SCHAR_MIN;
		RACSignal *signal = RCLBox(value);
		expect([signal toArray]).to(equal(@[ @(value) ]));
	});

	it(@"should create a constant signal of unsigned char", ^{
		unsigned char value = UCHAR_MAX;
		RACSignal *signal = RCLBox(value);
		expect([signal toArray]).to(equal(@[ @(value) ]));
	});

	it(@"should create a constant signal of float", ^{
		RACSignal *signal = RCLBox(FLT_MAX);
		expect([signal toArray]).to(equal(@[ @(FLT_MAX) ]));
	});

	it(@"should create a constant signal of double", ^{
		RACSignal *signal = RCLBox(DBL_MAX);
		expect([signal toArray]).to(equal(@[ @(DBL_MAX) ]));
	});

	it(@"should create a constant signal of CGRect", ^{
		CGRect rect = CGRectMake(1, 2, 3, 4);
		RACSignal *signal = RCLBox(rect);
		expect([signal toArray]).to(equal(@[ [NSValue med_valueWithRect:rect] ]));
	});

	it(@"should create a constant signal of CGSize", ^{
		CGSize size = CGSizeMake(5, 10);
		RACSignal *signal = RCLBox(size);
		expect([signal toArray]).to(equal(@[ [NSValue med_valueWithSize:size] ]));
	});

	it(@"should create a constant signal of CGPoint", ^{
		CGPoint point = CGPointMake(5, 10);
		RACSignal *signal = RCLBox(point);
		expect([signal toArray]).to(equal(@[ [NSValue med_valueWithPoint:point] ]));
	});
});

QuickSpecEnd
