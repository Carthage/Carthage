//
//  CGGeometry+MEDConvenienceAdditions.m
//  Archimedes
//
//  Created by Justin Spahr-Summers on 18.01.12.
//  Copyright 2012 GitHub. All rights reserved.
//

/*

Portions copyright (c) 2012, Bitswift, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 * Neither the name of the Bitswift, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/

#import <Foundation/Foundation.h>
#import "CGGeometry+MEDConvenienceAdditions.h"

// Conditionalizes fmax() and similar floating-point functions based on argument
// type, so they compile without casting on both OS X and iOS.
#import <tgmath.h>

// tgmath functions aren't used on iOS when modules are enabled. Work around
// this by redeclaring things here. http://www.openradar.me/16744288
#undef fmax
#define fmax(__x, __y) __tg_fmax(__tg_promote2((__x), (__y))(__x), \
                                 __tg_promote2((__x), (__y))(__y))
#undef floor
#define floor(__x) __tg_floor(__tg_promote1((__x))(__x))

#undef cos
#define cos(__x) __tg_cos(__tg_promote1((__x))(__x))

#undef sin
#define sin(__x) __tg_sin(__tg_promote1((__x))(__x))

// Hide our crazy macros within the implementation.
#undef MEDRectDivide
#undef MEDRectDivideWithPadding

CGPoint MEDRectCenterPoint(CGRect rect) {
	return CGPointMake(CGRectGetMinX(rect) + CGRectGetWidth(rect) / 2, CGRectGetMinY(rect) + CGRectGetHeight(rect) / 2);
}

CGRect MEDRectRemainder(CGRect rect, CGFloat amount, CGRectEdge edge) {
	CGRect slice, remainder;
	CGRectDivide(rect, &slice, &remainder, amount, edge);

	return remainder;
}

CGRect MEDRectSlice(CGRect rect, CGFloat amount, CGRectEdge edge) {
	CGRect slice, remainder;
	CGRectDivide(rect, &slice, &remainder, amount, edge);

	return slice;
}

CGRect MEDRectGrow(CGRect rect, CGFloat amount, CGRectEdge edge) {
	switch (edge) {
		case CGRectMinXEdge:
			return CGRectMake(CGRectGetMinX(rect) - amount, CGRectGetMinY(rect), CGRectGetWidth(rect) + amount, CGRectGetHeight(rect));

		case CGRectMinYEdge:
			return CGRectMake(CGRectGetMinX(rect), CGRectGetMinY(rect) - amount, CGRectGetWidth(rect), CGRectGetHeight(rect) + amount);

		case CGRectMaxXEdge:
			return CGRectMake(CGRectGetMinX(rect), CGRectGetMinY(rect), CGRectGetWidth(rect) + amount, CGRectGetHeight(rect));

		case CGRectMaxYEdge:
			return CGRectMake(CGRectGetMinX(rect), CGRectGetMinY(rect), CGRectGetWidth(rect), CGRectGetHeight(rect) + amount);

		default:
			NSCAssert(NO, @"Unrecognized CGRectEdge %i", (int)edge);
			return CGRectNull;
	}
}

void MEDRectDivideWithPadding(CGRect rect, CGRect *slicePtr, CGRect *remainderPtr, CGFloat sliceAmount, CGFloat padding, CGRectEdge edge) {
	CGRect slice;

	// slice
	CGRectDivide(rect, &slice, &rect, sliceAmount, edge);
	if (slicePtr) *slicePtr = slice;

	// padding / remainder
	CGRectDivide(rect, &slice, &rect, padding, edge);
	if (remainderPtr) *remainderPtr = rect;
}

CGRect MEDRectAlignWithRect(CGRect rect, CGRect referenceRect, CGRectEdge edge) {
	CGPoint origin;

	switch (edge) {
		case CGRectMinXEdge:
			origin = CGPointMake(CGRectGetMinX(referenceRect), CGRectGetMinY(rect));
			break;

		case CGRectMinYEdge:
			origin = CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(referenceRect));
			break;

		case CGRectMaxXEdge:
			origin = CGPointMake(CGRectGetMaxX(referenceRect) - CGRectGetWidth(rect), CGRectGetMinY(rect));
			break;

		case CGRectMaxYEdge:
			origin = CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(referenceRect) - CGRectGetHeight(rect));
			break;

		default:
			NSCAssert(NO, @"Unrecognized CGRectEdge %i", (int)edge);
			return CGRectNull;
	}

	return (CGRect){ .origin = origin, .size = rect.size };
}

CGRect MEDRectCenterInRect(CGRect inner, CGRect outer)
{
	CGPoint origin = {
		.x = CGRectGetMidX(outer) - CGRectGetWidth(inner)  / 2,
		.y = CGRectGetMidY(outer) - CGRectGetHeight(inner) / 2
	};

	return (CGRect){ .origin = origin, .size = inner.size };
}

CGRect MEDRectFloor(CGRect rect) {
	#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
		return CGRectMake(floor(rect.origin.x), floor(rect.origin.y), floor(rect.size.width), floor(rect.size.height));
	#elif TARGET_OS_MAC
		return CGRectMake(floor(rect.origin.x), ceil(rect.origin.y), floor(rect.size.width), floor(rect.size.height));
	#endif
}

CGRect MEDRectMakeInverted(CGRect containingRect, CGFloat x, CGFloat y, CGFloat width, CGFloat height) {
	CGRect rect = CGRectMake(x, y, width, height);
	return MEDRectInvert(containingRect, rect);
}

CGRect MEDRectInvert(CGRect containingRect, CGRect rect) {
	return CGRectMake(CGRectGetMinX(rect), CGRectGetHeight(containingRect) - CGRectGetMaxY(rect), CGRectGetWidth(rect), CGRectGetHeight(rect));
}

bool MEDRectEqualToRectWithAccuracy(CGRect rect, CGRect rect2, CGFloat epsilon) {
	return MEDPointEqualToPointWithAccuracy(rect.origin, rect2.origin, epsilon) && MEDSizeEqualToSizeWithAccuracy(rect.size, rect2.size, epsilon);
}

CGRect MEDRectWithSize(CGSize size) {
	return CGRectMake(0, 0, size.width, size.height);
}

CGRect MEDRectConvertToUnitRect(CGRect rect) {
	CGAffineTransform unitTransform = CGAffineTransformMakeScale(1 / CGRectGetWidth(rect), 1 / CGRectGetHeight(rect));
	return CGRectApplyAffineTransform(rect, unitTransform);
}

CGRect MEDRectConvertFromUnitRect(CGRect rect, CGRect destinationRect) {
	CGAffineTransform unitTransform = CGAffineTransformMakeScale(CGRectGetWidth(rect), CGRectGetHeight(rect));
	return CGRectApplyAffineTransform(destinationRect, unitTransform);
}

bool MEDSizeEqualToSizeWithAccuracy(CGSize size, CGSize size2, CGFloat epsilon) {
	return (fabs(size.width - size2.width) <= epsilon) && (fabs(size.height - size2.height) <= epsilon);
}

CGSize MEDSizeScale(CGSize size, CGFloat scale) {
	return CGSizeMake(size.width * scale, size.height * scale);
}

CGSize MEDSizeScaleAspectFit(CGSize size, CGSize maxSize) {
	CGFloat originalAspectRatio = size.width / size.height;
	CGFloat maxAspectRatio = maxSize.width / maxSize.height;
	CGSize newSize = maxSize;
	// The largest dimension will be the `maxSize`, and then we need to scale
	// the other dimension down relative to it, while maintaining the aspect
	// ratio.
	if (originalAspectRatio > maxAspectRatio) {
		newSize.height = maxSize.width / originalAspectRatio;
	} else {
		newSize.width = maxSize.height * originalAspectRatio;
	}

	return newSize;
}

CGSize MEDSizeScaleAspectFill(CGSize size, CGSize minSize) {
	CGFloat scaleWidth = minSize.width / size.width;
	CGFloat scaleHeight = minSize.height / size.height;

	CGFloat scale = fmax(scaleWidth, scaleHeight);
	CGFloat newWidth = size.width * scale;
	CGFloat newHeight = size.height * scale;

	return CGSizeMake(newWidth, newHeight);
}

CGPoint MEDPointFloor(CGPoint point) {
	#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
		return CGPointMake(floor(point.x), floor(point.y));
	#elif TARGET_OS_MAC
		return CGPointMake(floor(point.x), ceil(point.y));
	#endif
}

bool MEDPointEqualToPointWithAccuracy(CGPoint p, CGPoint q, CGFloat epsilon) {
	return (fabs(p.x - q.x) <= epsilon) && (fabs(p.y - q.y) <= epsilon);
}

CGFloat MEDPointDotProduct(CGPoint point, CGPoint point2) {
	return (point.x * point2.x + point.y * point2.y);
}

CGPoint MEDPointScale(CGPoint point, CGFloat scale) {
	return CGPointMake(point.x * scale, point.y * scale);
}

CGFloat MEDPointLength(CGPoint point) {
	return (CGFloat)sqrt(MEDPointDotProduct(point, point));
}

CGPoint MEDPointNormalize(CGPoint point) {
	CGFloat len = MEDPointLength(point);
	if (len > 0) return MEDPointScale(point, 1/len);

	return point;
}

CGPoint MEDPointProject(CGPoint point, CGPoint direction) {
	CGPoint normalizedDirection = MEDPointNormalize(direction);
	CGFloat distance = MEDPointDotProduct(point, normalizedDirection);

	return MEDPointScale(normalizedDirection, distance);
}

CGPoint MEDPointProjectAlongAngle(CGPoint point, CGFloat angleInDegrees) {
	CGFloat angleInRads = (CGFloat)(angleInDegrees * M_PI / 180);
	CGPoint direction = CGPointMake(cos(angleInRads), sin(angleInRads));
	return MEDPointProject(point, direction);
}

CGFloat MEDPointAngleInDegrees(CGPoint point) {
	return (CGFloat)(atan2(point.y, point.x) * 180 / M_PI);
}

CGPoint MEDPointAdd(CGPoint p1, CGPoint p2) {
	return CGPointMake(p1.x + p2.x, p1.y + p2.y);
}

CGPoint MEDPointSubtract(CGPoint p1, CGPoint p2) {
	return CGPointMake(p1.x - p2.x, p1.y - p2.y);
}
