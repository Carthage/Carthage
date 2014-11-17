//
//  MEDCGGeometryAdditionsSpec.m
//  Archimedes
//
//  Created by Justin Spahr-Summers on 18.01f.12.
//  Copyright 2012 GitHub. All rights reserved.
//

/*

Portions copyright (c) 2012, Bitswift, Inc.
All rights reserved.

Redistribution and use in source and binary forms, With or Without modification, are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 * Neither the name of the Bitswift, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software Without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/

#import <Archimedes/Archimedes.h>
#import <Nimble/Nimble.h>
#import <Quick/Quick.h>

#import "MEDGeometryTestObject.h"

QuickSpecBegin(CGGeometryAdditions)

qck_describe(@"MEDRectDivide macro", ^{
	CGRect rect = CGRectMake(10, 20, 30, 40);

	qck_it(@"should accept NULLs", ^{
		MEDRectDivide(rect, NULL, NULL, 10, CGRectMinXEdge);
	});

	qck_it(@"should accept pointers", ^{
		CGRect slice, remainder;
		MEDRectDivide(rect, &slice, &remainder, 10, CGRectMinXEdge);

		expect(MEDBox(slice)).to(equal(MEDBox(CGRectMake(10, 20, 10, 40))));
		expect(MEDBox(remainder)).to(equal(MEDBox(CGRectMake(20, 20, 20, 40))));
	});

	qck_it(@"should accept raw variables", ^{
		CGRect slice, remainder;
		MEDRectDivide(rect, slice, remainder, 10, CGRectMinXEdge);

		expect(MEDBox(slice)).to(equal(MEDBox(CGRectMake(10, 20, 10, 40))));
		expect(MEDBox(remainder)).to(equal(MEDBox(CGRectMake(20, 20, 20, 40))));
	});

	qck_it(@"should accept properties", ^{
		MEDGeometryTestObject *obj = [[MEDGeometryTestObject alloc] init];
		expect(obj).notTo(beNil());

		MEDRectDivide(rect, obj.slice, obj.remainder, 10, CGRectMinXEdge);

		expect(MEDBox(obj.slice)).to(equal(MEDBox(CGRectMake(10, 20, 10, 40))));
		expect(MEDBox(obj.remainder)).to(equal(MEDBox(CGRectMake(20, 20, 20, 40))));
	});
});

qck_describe(@"MEDRectCenterPoint", ^{
	qck_it(@"should return the center of a valid rectangle", ^{
		CGRect rect = CGRectMake(10, 20, 30, 40);
		expect(MEDBox(MEDRectCenterPoint(rect))).to(equal(MEDBox(CGPointMake(25, 40))));
	});

	qck_it(@"should return the center of an empty rectangle", ^{
		CGRect rect = CGRectMake(10, 20, 0, 0);
		expect(MEDBox(MEDRectCenterPoint(rect))).to(equal(MEDBox(CGPointMake(10, 20))));
	});

	qck_it(@"should return non-integral center points", ^{
		CGRect rect = CGRectMake(10, 20, 15, 7);
		expect(MEDBox(MEDRectCenterPoint(rect))).to(equal(MEDBox(CGPointMake(17.5f, 23.5f))));
	});
});

qck_describe(@"MEDRectDivideWithPadding", ^{
	CGRect rect = CGRectMake(50, 50, 100, 100);

	__block CGRect slice, remainder;
	qck_beforeEach(^{
		slice = CGRectZero;
		remainder = CGRectZero;
	});

	qck_it(@"should divide With padding", ^{
		CGRect expectedSlice = CGRectMake(50, 50, 40, 100);
		CGRect expectedRemainder = CGRectMake(90 + 10, 50, 50, 100);

		MEDRectDivideWithPadding(rect, &slice, &remainder, 40, 10, CGRectMinXEdge);

		expect(MEDBox(slice)).to(equal(MEDBox(expectedSlice)));
		expect(MEDBox(remainder)).to(equal(MEDBox(expectedRemainder)));
	});

	qck_it(@"should divide With a null slice", ^{
		CGRect expectedRemainder = CGRectMake(90 + 10, 50, 50, 100);

		MEDRectDivideWithPadding(rect, NULL, &remainder, 40, 10, CGRectMinXEdge);
		expect(MEDBox(remainder)).to(equal(MEDBox(expectedRemainder)));
	});

	qck_it(@"should divide With a null remainder", ^{
		CGRect expectedSlice = CGRectMake(50, 50, 40, 100);
		MEDRectDivideWithPadding(rect, &slice, NULL, 40, 10, CGRectMinXEdge);
		expect(MEDBox(slice)).to(equal(MEDBox(expectedSlice)));
	});

	qck_it(@"should divide With no space for remainder", ^{
		CGRect expectedSlice = CGRectMake(50, 50, 95, 100);
		MEDRectDivideWithPadding(rect, &slice, &remainder, 95, 10, CGRectMinXEdge);
		expect(MEDBox(slice)).to(equal(MEDBox(expectedSlice)));
		expect(@(CGRectIsEmpty(remainder))).to(beTruthy());
	});

	qck_it(@"should accept raw variables", ^{
		CGRect expectedSlice = CGRectMake(50, 50, 40, 100);
		CGRect expectedRemainder = CGRectMake(90 + 10, 50, 50, 100);

		MEDRectDivideWithPadding(rect, slice, remainder, 40, 10, CGRectMinXEdge);

		expect(MEDBox(slice)).to(equal(MEDBox(expectedSlice)));
		expect(MEDBox(remainder)).to(equal(MEDBox(expectedRemainder)));
	});

	qck_it(@"should accept properties", ^{
		MEDGeometryTestObject *obj = [[MEDGeometryTestObject alloc] init];
		expect(MEDBox(obj)).notTo(beNil());

		CGRect expectedSlice = CGRectMake(50, 50, 40, 100);
		CGRect expectedRemainder = CGRectMake(90 + 10, 50, 50, 100);

		MEDRectDivideWithPadding(rect, obj.slice, obj.remainder, 40, 10, CGRectMinXEdge);

		expect(MEDBox(obj.slice)).to(equal(MEDBox(expectedSlice)));
		expect(MEDBox(obj.remainder)).to(equal(MEDBox(expectedRemainder)));
	});
});

qck_describe(@"MEDRectAlignWithRect", ^{
	CGRect rect = CGRectMake(0, 0, 10, 10);
	CGRect referenceRect = CGRectMake(10, 20, 30, 40);

	qck_describe(@"when aligning on the min x edge", ^{
		qck_it(@"should return an aligned rectangle", ^{
			CGRect aligned = MEDRectAlignWithRect(rect, referenceRect, CGRectMinXEdge);

			expect(MEDBox(aligned)).to(equal(MEDBox(CGRectMake(10, 0, 10, 10))));
		});
	});

	qck_describe(@"when aligning on the min y edge", ^{
		qck_it(@"should return an aligned rectangle", ^{
			CGRect aligned = MEDRectAlignWithRect(rect, referenceRect, CGRectMinYEdge);

			expect(MEDBox(aligned)).to(equal(MEDBox(CGRectMake(0, 20, 10, 10))));
		});
	});

	qck_describe(@"when aligning on the max x edge", ^{
		qck_it(@"should return an aligned rectangle", ^{
			CGRect aligned = MEDRectAlignWithRect(rect, referenceRect, CGRectMaxXEdge);

			expect(MEDBox(aligned)).to(equal(MEDBox(CGRectMake(30, 0, 10, 10))));
		});
	});

	qck_describe(@"when aligning on the max y edge", ^{
		qck_it(@"should return an aligned rectangle", ^{
			CGRect aligned = MEDRectAlignWithRect(rect, referenceRect, CGRectMaxYEdge);

			expect(MEDBox(aligned)).to(equal(MEDBox(CGRectMake(0, 50, 10, 10))));
		});
	});
});

qck_describe(@"MEDRectCenterInRect", ^{
	qck_it(@"should return a rectangle centered in another rectangle", ^{
		CGRect inner = CGRectMake(0, 0, 10, 10);
		CGRect outer = CGRectMake(0, 0, 20, 20);

		expect(MEDBox(MEDRectCenterInRect(inner, outer))).to(equal(MEDBox(CGRectMake(5, 5, 10, 10))));
	});

	qck_it(@"should return a non-integral rectangle", ^{
		CGRect inner = CGRectMake(0, 0, 10, 10);
		CGRect outer = CGRectMake(0, 0, 19, 19);

		expect(MEDBox(MEDRectCenterInRect(inner, outer))).to(equal(MEDBox(CGRectMake(4.5f, 4.5f, 10, 10))));
	});

	qck_describe(@"qck_it should handle centering bigger rectanlges in smaller ones", ^{
		CGRect inner = CGRectMake(0, 0, 10, 10);
		CGRect outer = CGRectZero;

		expect(MEDBox(MEDRectCenterInRect(inner, outer))).to(equal(MEDBox(CGRectMake(-5, -5, 10, 10))));
	});
});

qck_describe(@"MEDRectRemainder", ^{
	qck_it(@"should return the rectangle's remainder", ^{
		CGRect rect = CGRectMake(100, 100, 100, 100);

		CGRect result = MEDRectRemainder(rect, 25, CGRectMaxXEdge);
		CGRect expectedResult = CGRectMake(100, 100, 75, 100);

		expect(MEDBox(result)).to(equal(MEDBox(expectedResult)));
	});
});

qck_describe(@"MEDRectSlice", ^{
	qck_it(@"should return the rectangle's slice", ^{
		CGRect rect = CGRectMake(100, 100, 100, 100);

		CGRect result = MEDRectSlice(rect, 25, CGRectMaxXEdge);
		CGRect expectedResult = CGRectMake(175, 100, 25, 100);

		expect(MEDBox(result)).to(equal(MEDBox(expectedResult)));
	});
});

qck_describe(@"MEDRectGrow", ^{
	qck_it(@"should return a larger rectangle", ^{
		CGRect rect = CGRectMake(100, 100, 100, 100);

		CGRect result = MEDRectGrow(rect, 25, CGRectMinXEdge);
		CGRect expectedResult = CGRectMake(75, 100, 125, 100);
		expect(MEDBox(result)).to(equal(MEDBox(expectedResult)));
	});
});

qck_describe(@"MEDRectFloor", ^{
	qck_it(@"leaves integers untouched", ^{
		CGRect rect = CGRectMake(-10, 20, -30, 40);
		CGRect result = MEDRectFloor(rect);
		expect(MEDBox(result)).to(equal(MEDBox(rect)));
	});

	#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
		qck_it(@"rounds down", ^{
			CGRect rect = CGRectMake(10.1f, 1.1f, -3.4f, -4.7f);

			CGRect result = MEDRectFloor(rect);
			CGRect expectedResult = CGRectMake(10, 1, -4, -5);
			expect(MEDBox(result)).to(equal(MEDBox(expectedResult)));
		});
	#elif TARGET_OS_MAC
		qck_it(@"rounds down, except in Y", ^{
			CGRect rect = CGRectMake(10.1, 1.1, -3.4, -4.7);

			CGRect result = MEDRectFloor(rect);
			CGRect expectedResult = CGRectMake(10, 2, -4, -5);
			expect(MEDBox(result)).to(equal(MEDBox(expectedResult)));
		});
	#endif

	qck_it(@"leaves CGRectNull untouched", ^{
		CGRect rect = CGRectNull;
		CGRect result = MEDRectFloor(rect);
		expect(MEDBox(result)).to(equal(MEDBox(rect)));
	});

	qck_it(@"leaves CGRectInfinite untouched", ^{
		CGRect rect = CGRectInfinite;
		CGRect result = MEDRectFloor(rect);
		expect(MEDBox(result)).to(equal(MEDBox(rect)));
	});
});

qck_describe(@"inverted rectangles", ^{
	qck_it(@"should create an inverted rectangle Within a containing rectangle", ^{
		CGRect containingRect = CGRectMake(0, 0, 100, 100);

		// Bottom Left
		CGRect expectedResult = CGRectMake(0, CGRectGetHeight(containingRect) - 20 - 50, 50, 50);

		CGRect result = MEDRectMakeInverted(containingRect, 0, 20, 50, 50);
		expect(MEDBox(result)).to(equal(MEDBox(expectedResult)));
	});

	qck_it(@"should invert a rectangle Within a containing rectangle", ^{
		CGRect rect = CGRectMake(0, 20, 50, 50);
		CGRect containingRect = CGRectMake(0, 0, 100, 100);

		// Bottom Left
		CGRect expectedResult = CGRectMake(0, CGRectGetHeight(containingRect) - 20 - 50, 50, 50);

		CGRect result = MEDRectInvert(containingRect, rect);
		expect(MEDBox(result)).to(equal(MEDBox(expectedResult)));
	});
});

qck_describe(@"MEDRectWithSize", ^{
	qck_it(@"should return a rectangle With a valid size", ^{
		CGRect rect = MEDRectWithSize(CGSizeMake(20, 40));
		expect(MEDBox(rect)).to(equal(MEDBox(CGRectMake(0, 0, 20, 40))));
	});

	qck_it(@"should return a rectangle With zero size", ^{
		CGRect rect = MEDRectWithSize(CGSizeZero);
		expect(MEDBox(rect)).to(equal(MEDBox(CGRectZero)));
	});
});

qck_describe(@"MEDRectConvertToUnitRect", ^{
	qck_it(@"should return a rectangle With unit coordinates", ^{
		CGRect rect = MEDRectConvertToUnitRect(CGRectMake(0, 0, 100, 100));
		expect(MEDBox(rect)).to(equal(MEDBox(CGRectMake(0, 0, 1, 1))));
	});
});

qck_describe(@"MEDRectConvertFromUnitRect", ^{
	qck_it(@"should return a rectangle With non-unit coordinates", ^{
		CGRect viewRect = CGRectMake(0, 0, 100, 100);
		CGRect unitRect = CGRectMake(0, 0, 0.5, 0.5);
		CGRect rect = MEDRectConvertFromUnitRect(unitRect, viewRect);
		expect(MEDBox(rect)).to(equal(MEDBox(CGRectMake(0, 0, 50, 50))));
	});
});

qck_describe(@"MEDPointFloor", ^{
	#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
		qck_it(@"rounds components up and left", ^{
			CGPoint point = CGPointMake(0.5f, 0.49f);
			CGPoint point2 = CGPointMake(-0.5f, -0.49f);
			expect(@(CGPointEqualToPoint(MEDPointFloor(point), CGPointMake(0, 0)))).to(beTruthy());
			expect(@(CGPointEqualToPoint(MEDPointFloor(point2), CGPointMake(-1, -1)))).to(beTruthy());
		});
	#elif TARGET_OS_MAC
		qck_it(@"rounds components up and left", ^{
			CGPoint point = CGPointMake(0.5, 0.49);
			CGPoint point2 = CGPointMake(-0.5, -0.49);
			expect(@(CGPointEqualToPoint(MEDPointFloor(point), CGPointMake(0, 1)))).to(beTruthy());
			expect(@(CGPointEqualToPoint(MEDPointFloor(point2), CGPointMake(-1, 0)))).to(beTruthy());
		});
	#endif
});

qck_describe(@"equality With accuracy", ^{
	CGRect rect = CGRectMake(0.5f, 1.5f, 15, 20);
	CGFloat epsilon = 0.6f;

	CGRect closeRect = CGRectMake(1, 1, 15.5f, 19.75f);
	CGRect farRect = CGRectMake(1.5f, 11.5f, 20, 20);

	qck_it(@"compares two points that are close enough", ^{
		expect(@(MEDPointEqualToPointWithAccuracy(rect.origin, closeRect.origin, epsilon))).to(beTruthy());
	});

	qck_it(@"compares two points that are too far from each other", ^{
		expect(@(MEDPointEqualToPointWithAccuracy(rect.origin, farRect.origin, epsilon))).to(beFalsy());
	});

	qck_it(@"compares two rectangles that are close enough", ^{
		expect(@(MEDRectEqualToRectWithAccuracy(rect, closeRect, epsilon))).to(beTruthy());
	});

	qck_it(@"compares two rectangles that are too far from each other", ^{
		expect(@(MEDRectEqualToRectWithAccuracy(rect, farRect, epsilon))).to(beFalsy());
	});

	qck_it(@"compares two sizes that are close enough", ^{
		expect(@(MEDSizeEqualToSizeWithAccuracy(rect.size, closeRect.size, epsilon))).to(beTruthy());
	});

	qck_it(@"compares two sizes that are too far from each other", ^{
		expect(@(MEDSizeEqualToSizeWithAccuracy(rect.size, farRect.size, epsilon))).to(beFalsy());
	});
});

qck_describe(@"MEDSizeScale", ^{
	qck_it(@"should scale each component", ^{
		CGSize original = CGSizeMake(-5, 3.4f);
		CGFloat scale = -3.5f;

		CGSize scaledSize = MEDSizeScale(original, scale);
		CGSize expected = CGSizeMake(17.5f, -11.9f);

		expect(@(scaledSize.width)).to(beCloseTo(@(expected.width)));
		expect(@(scaledSize.height)).to(beCloseTo(@(expected.height)));
	});
});

qck_describe(@"MEDSizeScaleAspectFqck_it", ^{
	CGSize containingSize = CGSizeMake(75, 75);

	qck_it(@"should return a size which fits inside the given size when the width is bigger", ^{
		CGSize sizeToScale = CGSizeMake(100, 75);
		CGSize size = MEDSizeScaleAspectFit(sizeToScale, containingSize);
		expect(MEDBox(size)).to(equal(MEDBox(CGSizeMake(75, 56.25))));
	});

	qck_it(@"should return a size which fits inside the given size when the height is bigger", ^{
		CGSize sizeToScale = CGSizeMake(75, 100);
		CGSize size = MEDSizeScaleAspectFit(sizeToScale, containingSize);
		expect(MEDBox(size)).to(equal(MEDBox(CGSizeMake(56.25, 75))));
	});
});

qck_describe(@"MEDSizeScaleAspectFill", ^{
	CGSize containingSize = CGSizeMake(75, 75);

	qck_it(@"should return a size which fills the given size when the width is bigger", ^{
		CGSize sizeToScale = CGSizeMake(100, 75);
		CGSize size = MEDSizeScaleAspectFill(sizeToScale, containingSize);
		expect(MEDBox(size)).to(equal(MEDBox(CGSizeMake(100, 75))));
	});

	qck_it(@"should return a size which fills the given size when the height is bigger", ^{
		CGSize sizeToScale = CGSizeMake(75, 100);
		CGSize size = MEDSizeScaleAspectFill(sizeToScale, containingSize);
		expect(MEDBox(size)).to(equal(MEDBox(CGSizeMake(75, 100))));
	});
});

qck_describe(@"MEDPointAdd", ^{
	qck_it(@"adds two points together, element-wise", ^{
		CGPoint point1 = CGPointMake(-1, 5);
		CGPoint point2 = CGPointMake(10, 12);
		CGPoint sum = MEDPointAdd(point1, point2);
		expect(MEDBox(sum)).to(equal(MEDBox(CGPointMake(9, 17))));
	});
});

qck_describe(@"MEDPointSubtract", ^{
	qck_it(@"adds two points together, element-wise", ^{
		CGPoint point1 = CGPointMake(-1, 5);
		CGPoint point2 = CGPointMake(10, 12);
		CGPoint diff = MEDPointSubtract(point1, point2);
		expect(MEDBox(diff)).to(equal(MEDBox(CGPointMake(-11, -7))));
	});
});

QuickSpecEnd
