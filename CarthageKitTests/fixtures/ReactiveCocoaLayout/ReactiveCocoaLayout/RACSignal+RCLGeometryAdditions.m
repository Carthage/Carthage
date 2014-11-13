//
//  RACSignal+RCLGeometryAdditions.m
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-12.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "RACSignal+RCLGeometryAdditions.h"
#import "RACSignal+RCLWritingDirectionAdditions.h"
#import <Archimedes/Archimedes.h>
#import <ReactiveCocoa/ReactiveCocoa.h>

// When any signal sends an NSNumber, sorts the latest values from all of them,
// and sends either the minimum or the maximum.
static RACSignal *latestSortedNumber(NSArray *signals, BOOL minimum) {
	NSCParameterAssert(signals != nil);

	return [[[[RACSignal combineLatest:signals]
		map:^ id (RACTuple *t) {
			NSMutableArray *values = [t.allObjects mutableCopy];

			[values removeObject:NSNull.null];
			if (values.count == 0) return nil;

			[values sortUsingSelector:@selector(compare:)];

			if (minimum) {
				return values[0];
			} else {
				return values.lastObject;
			}
		}]
		filter:^ BOOL (NSNumber *value) {
			return value != nil;
		}]
		distinctUntilChanged];
}

// A binary operator accepting two numbers and returning a number.
typedef CGFloat (^RCLBinaryOperator)(CGFloat, CGFloat);

// Used from combineSignalsWithOperator() to combine two numbers using an
// arbitrary binary operator.
static NSNumber *combineNumbersWithOperator(NSNumber *a, NSNumber *b, RCLBinaryOperator operator) {
	NSCAssert([a isKindOfClass:NSNumber.class], @"Expected a number, not %@", a);
	NSCAssert([b isKindOfClass:NSNumber.class], @"Expected a number, not %@", b);

	return @(operator(a.doubleValue, b.doubleValue));
}

// Used from combineSignalsWithOperator() to combine two values using an
// arbitrary binary operator.
static NSValue *combineValuesWithOperator(NSValue *a, NSValue *b, RCLBinaryOperator operator) {
	NSCAssert([a isKindOfClass:NSValue.class], @"Expected a value, not %@", a);
	NSCAssert([b isKindOfClass:NSValue.class], @"Expected a value, not %@", b);
	NSCAssert(a.med_geometryStructType == b.med_geometryStructType, @"Values do not contain the same type of geometry structure: %@, %@", a, b);

	switch (a.med_geometryStructType) {
		case MEDGeometryStructTypePoint: {
			CGPoint pointA = a.med_pointValue;
			CGPoint pointB = b.med_pointValue;

			CGPoint result = CGPointMake(operator(pointA.x, pointB.x), operator(pointA.y, pointB.y));
			return MEDBox(result);
		}

		case MEDGeometryStructTypeSize: {
			CGSize sizeA = a.med_sizeValue;
			CGSize sizeB = b.med_sizeValue;

			CGSize result = CGSizeMake(operator(sizeA.width, sizeB.width), operator(sizeA.height, sizeB.height));
			return MEDBox(result);
		}

		case MEDGeometryStructTypeRect:
		default:
			NSCAssert(NO, @"Values must contain CGSizes or CGPoints: %@, %@", a, b);
			return nil;
	}
}

// Combines the values of the given signals using the given binary operator,
// applied left-to-right across the signal values.
//
// The values may be CGFloats, CGSizes, or CGPoints, but all signals must send
// values of the same type.
//
// Returns a signal of results, using the same type as the input values.
static RACSignal *combineSignalsWithOperator(NSArray *signals, RCLBinaryOperator operator) {
	NSCParameterAssert(signals != nil);
	NSCParameterAssert(signals.count > 0);
	NSCParameterAssert(operator != nil);

	return [[[RACSignal combineLatest:signals]
		map:^(RACTuple *values) {
			return values.allObjects.rac_sequence;
		}]
		map:^(RACSequence *values) {
			id result = values.head;
			BOOL isNumber = [result isKindOfClass:NSNumber.class];

			for (id value in values.tail) {
				if (isNumber) {
					result = combineNumbersWithOperator(result, value, operator);
				} else {
					result = combineValuesWithOperator(result, value, operator);
				}
			}

			return result;
		}];
}

// Combines the CGRectEdge corresponding to a layout attribute, and the values
// from the given signals.
//
// attribute   - The layout attribute to retrieve the edge for. If the layout
//				 attribute does not describe one of the edges of a rectangle, no
//				 `edge` will be provided to the `reduceBlock`. Must not be
//				 NSLayoutAttributeBaseline.
// signals	   - The signals to combine the values of. This must contain at
//				 least one signal.
// reduceBlock - A block which combines the NSNumber-boxed CGRectEdge (if
//				 `attribute` corresponds to one), or `nil` (if it does not) and
//				 the values of each signal in the `signals` array.
//
// Returns a signal of reduced values.
static RACSignal *combineAttributeAndSignals(NSLayoutAttribute attribute, NSArray *signals, id reduceBlock) {
	NSCParameterAssert(attribute != NSLayoutAttributeBaseline);
	NSCParameterAssert(attribute != NSLayoutAttributeNotAnAttribute);
	NSCParameterAssert(signals.count > 0);

	RACSignal *edgeSignal = nil;
	NSMutableArray *mutableSignals = [signals mutableCopy];

	switch (attribute) {
		// TODO: Consider modified view coordinate systems?
		case NSLayoutAttributeLeft:
			edgeSignal = [RACSignal return:@(CGRectMinXEdge)];
			break;

		case NSLayoutAttributeRight:
			edgeSignal = [RACSignal return:@(CGRectMaxXEdge)];
			break;

	#ifdef RCL_FOR_IPHONE
		case NSLayoutAttributeTop:
			edgeSignal = [RACSignal return:@(CGRectMinYEdge)];
			break;

		case NSLayoutAttributeBottom:
			edgeSignal = [RACSignal return:@(CGRectMaxYEdge)];
			break;
	#else
		case NSLayoutAttributeTop:
			edgeSignal = [RACSignal return:@(CGRectMaxYEdge)];
			break;

		case NSLayoutAttributeBottom:
			edgeSignal = [RACSignal return:@(CGRectMinYEdge)];
			break;
	#endif

		case NSLayoutAttributeLeading:
		case NSLayoutAttributeTrailing: {
			RACReplaySubject *edgeSubject = [RACReplaySubject replaySubjectWithCapacity:1];

			RACSignal *baseSignal = (attribute == NSLayoutAttributeLeading ? RACSignal.leadingEdgeSignal : RACSignal.trailingEdgeSignal);
			edgeSignal = [[baseSignal multicast:edgeSubject] autoconnect];

			// Terminate edgeSubject when one of the given signals completes
			// (doesn't really matter which one).
			mutableSignals[0] = [mutableSignals[0] doCompleted:^{
				[edgeSubject sendCompleted];
			}];

			break;
		}

		case NSLayoutAttributeWidth:
		case NSLayoutAttributeHeight:
		case NSLayoutAttributeCenterX:
		case NSLayoutAttributeCenterY:
			// No sensical edge for these attributes.
			edgeSignal = [RACSignal return:nil];
			break;

		default:
			NSCAssert(NO, @"Unrecognized NSLayoutAttribute: %li", (long)attribute);
			return nil;
	}

	[mutableSignals insertObject:edgeSignal atIndex:0];
	return [RACSignal combineLatest:mutableSignals reduce:reduceBlock];
}

@implementation RACSignal (RCLGeometryAdditions)

+ (RACSignal *)zero {
	return [RACSignal return:@0];
}

+ (RACSignal *)zeroRect {
	return [RACSignal return:[NSValue med_valueWithRect:CGRectZero]];
}

+ (RACSignal *)zeroSize {
	return [RACSignal return:[NSValue med_valueWithSize:CGSizeZero]];
}

+ (RACSignal *)zeroPoint {
	return [RACSignal return:[NSValue med_valueWithPoint:CGPointZero]];
}

+ (RACSignal *)rectsWithX:(RACSignal *)xSignal Y:(RACSignal *)ySignal width:(RACSignal *)widthSignal height:(RACSignal *)heightSignal {
	NSParameterAssert(xSignal != nil);
	NSParameterAssert(ySignal != nil);
	NSParameterAssert(widthSignal != nil);
	NSParameterAssert(heightSignal != nil);

	return [[RACSignal combineLatest:@[ xSignal, ySignal, widthSignal, heightSignal ] reduce:^(NSNumber *x, NSNumber *y, NSNumber *width, NSNumber *height) {
		NSAssert([x isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", xSignal, x);
		NSAssert([y isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", ySignal, y);
		NSAssert([width isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", widthSignal, width);
		NSAssert([height isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", heightSignal, height);

		return MEDBox(CGRectMake(x.doubleValue, y.doubleValue, width.doubleValue, height.doubleValue));
	}] setNameWithFormat:@"+rectsWithX: %@ Y: %@ width: %@ height: %@", xSignal, ySignal, widthSignal, heightSignal];
}

+ (RACSignal *)rectsWithOrigin:(RACSignal *)originSignal size:(RACSignal *)sizeSignal {
	NSParameterAssert(originSignal != nil);
	NSParameterAssert(sizeSignal != nil);

	return [[RACSignal combineLatest:@[ originSignal, sizeSignal ] reduce:^(NSValue *origin, NSValue *size) {
		NSAssert([origin isKindOfClass:NSValue.class] && origin.med_geometryStructType == MEDGeometryStructTypePoint, @"Value sent by %@ is not a CGPoint: %@", originSignal, origin);
		NSAssert([size isKindOfClass:NSValue.class] && size.med_geometryStructType == MEDGeometryStructTypeSize, @"Value sent by %@ is not a CGSize: %@", sizeSignal, size);

		CGPoint p = origin.med_pointValue;
		CGSize s = size.med_sizeValue;

		return MEDBox(CGRectMake(p.x, p.y, s.width, s.height));
	}] setNameWithFormat:@"+rectsWithOrigin: %@ size: %@", originSignal, sizeSignal];
}

+ (RACSignal *)rectsWithCenter:(RACSignal *)centerSignal size:(RACSignal *)sizeSignal {
	NSParameterAssert(centerSignal != nil);
	NSParameterAssert(sizeSignal != nil);

	return [[RACSignal combineLatest:@[ centerSignal, sizeSignal ] reduce:^(NSValue *center, NSValue *size) {
		NSAssert([center isKindOfClass:NSValue.class] && center.med_geometryStructType == MEDGeometryStructTypePoint, @"Value sent by %@ is not a CGPoint: %@", centerSignal, center);
		NSAssert([size isKindOfClass:NSValue.class] && size.med_geometryStructType == MEDGeometryStructTypeSize, @"Value sent by %@ is not a CGSize: %@", sizeSignal, size);

		CGPoint p = center.med_pointValue;
		CGSize s = size.med_sizeValue;

		return MEDBox(CGRectMake(p.x - s.width / 2, p.y - s.height / 2, s.width, s.height));
	}] setNameWithFormat:@"+rectsWithCenter: %@ size: %@", centerSignal, sizeSignal];
}

+ (RACSignal *)rectsWithSize:(RACSignal *)sizeSignal {
	return [[self rectsWithOrigin:self.zeroPoint size:sizeSignal] setNameWithFormat:@"+rectsWithSize: %@", sizeSignal];
}

- (RACSignal *)size {
	return [[self map:^(NSValue *value) {
		NSAssert([value isKindOfClass:NSValue.class] && value.med_geometryStructType == MEDGeometryStructTypeRect, @"Value sent by %@ is not a CGRect: %@", self, value);

		return MEDBox(value.med_rectValue.size);
	}] setNameWithFormat:@"[%@] -size", self.name];
}

- (RACSignal *)replaceSize:(RACSignal *)sizeSignal {
	return [[self.class rectsWithOrigin:self.origin size:sizeSignal] setNameWithFormat:@"[%@] -replaceSize: %@", self.name, sizeSignal];
}

+ (RACSignal *)sizesWithWidth:(RACSignal *)widthSignal height:(RACSignal *)heightSignal {
	NSParameterAssert(widthSignal != nil);
	NSParameterAssert(heightSignal != nil);

	return [[RACSignal combineLatest:@[ widthSignal, heightSignal ] reduce:^(NSNumber *width, NSNumber *height) {
		NSAssert([width isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", widthSignal, width);
		NSAssert([height isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", heightSignal, height);

		return MEDBox(CGSizeMake(width.doubleValue, height.doubleValue));
	}] setNameWithFormat:@"+sizesWithWidth: %@ height: %@", widthSignal, heightSignal];
}

- (RACSignal *)width {
	return [[self map:^(NSValue *value) {
		if (value.med_geometryStructType == MEDGeometryStructTypeRect) {
			return @(CGRectGetWidth(value.med_rectValue));
		} else {
			NSAssert(value.med_geometryStructType == MEDGeometryStructTypeSize, @"Unexpected type of value: %@", value);
			return @(value.med_sizeValue.width);
		}
	}] setNameWithFormat:@"[%@] -width", self.name];
}

- (RACSignal *)replaceWidth:(RACSignal *)widthSignal {
	NSParameterAssert(widthSignal != nil);

	return [[RACSignal combineLatest:@[ widthSignal, self ] reduce:^(NSNumber *width, NSValue *value) {
		if (value.med_geometryStructType == MEDGeometryStructTypeRect) {
			CGRect rect = value.med_rectValue;
			rect.size.width = width.doubleValue;
			return MEDBox(rect);
		} else {
			NSAssert(value.med_geometryStructType == MEDGeometryStructTypeSize, @"Unexpected type of value: %@", value);

			CGSize size = value.med_sizeValue;
			size.width = width.doubleValue;
			return MEDBox(size);
		}
	}] setNameWithFormat:@"[%@] -replaceWidth: %@", self.name, widthSignal];
}

- (RACSignal *)height {
	return [[self map:^(NSValue *value) {
		if (value.med_geometryStructType == MEDGeometryStructTypeRect) {
			return @(CGRectGetHeight(value.med_rectValue));
		} else {
			NSAssert(value.med_geometryStructType == MEDGeometryStructTypeSize, @"Unexpected type of value: %@", value);
			return @(value.med_sizeValue.height);
		}
	}] setNameWithFormat:@"[%@] -height", self.name];
}

- (RACSignal *)replaceHeight:(RACSignal *)heightSignal {
	NSParameterAssert(heightSignal != nil);

	return [[RACSignal combineLatest:@[ heightSignal, self ] reduce:^(NSNumber *height, NSValue *value) {
		if (value.med_geometryStructType == MEDGeometryStructTypeRect) {
			CGRect rect = value.med_rectValue;
			rect.size.height = height.doubleValue;
			return MEDBox(rect);
		} else {
			NSAssert(value.med_geometryStructType == MEDGeometryStructTypeSize, @"Unexpected type of value: %@", value);

			CGSize size = value.med_sizeValue;
			size.height = height.doubleValue;
			return MEDBox(size);
		}
	}] setNameWithFormat:@"[%@] -replaceHeight: %@", self.name, heightSignal];
}

- (RACSignal *)origin {
	return [[self map:^(NSValue *value) {
		NSAssert([value isKindOfClass:NSValue.class] && value.med_geometryStructType == MEDGeometryStructTypeRect, @"Value sent by %@ is not a CGRect: %@", self, value);

		return MEDBox(value.med_rectValue.origin);
	}] setNameWithFormat:@"[%@] -origin", self.name];
}

- (RACSignal *)replaceOrigin:(RACSignal *)originSignal {
	return [[self.class rectsWithOrigin:originSignal size:self.size] setNameWithFormat:@"[%@] -replaceOrigin: %@", self.name, originSignal];
}

- (RACSignal *)center {
	return [[self map:^(NSValue *value) {
		NSAssert([value isKindOfClass:NSValue.class] && value.med_geometryStructType == MEDGeometryStructTypeRect, @"Value sent by %@ is not a CGRect: %@", self, value);

		return MEDBox(MEDRectCenterPoint(value.med_rectValue));
	}] setNameWithFormat:@"[%@] -center", self.name];
}

+ (RACSignal *)pointsWithX:(RACSignal *)xSignal Y:(RACSignal *)ySignal {
	NSParameterAssert(xSignal != nil);
	NSParameterAssert(ySignal != nil);

	return [[RACSignal combineLatest:@[ xSignal, ySignal ] reduce:^(NSNumber *x, NSNumber *y) {
		NSAssert([x isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", xSignal, x);
		NSAssert([y isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", ySignal, y);

		return MEDBox(CGPointMake(x.doubleValue, y.doubleValue));
	}] setNameWithFormat:@"+pointsWithX: %@ Y: %@", xSignal, ySignal];
}

- (RACSignal *)x {
	return [[self map:^(NSValue *value) {
		NSAssert([value isKindOfClass:NSValue.class] && value.med_geometryStructType == MEDGeometryStructTypePoint, @"Value sent by %@ is not a CGPoint: %@", self, value);

		return @(value.med_pointValue.x);
	}] setNameWithFormat:@"[%@] -x", self.name];
} 

- (RACSignal *)replaceX:(RACSignal *)xSignal {
	return [[self.class pointsWithX:xSignal Y:self.y] setNameWithFormat:@"[%@] -replaceX: %@", self.name, xSignal];
}

- (RACSignal *)y {
	return [[self map:^(NSValue *value) {
		NSAssert([value isKindOfClass:NSValue.class] && value.med_geometryStructType == MEDGeometryStructTypePoint, @"Value sent by %@ is not a CGPoint: %@", self, value);

		return @(value.med_pointValue.y);
	}] setNameWithFormat:@"[%@] -y", self.name];
}

- (RACSignal *)replaceY:(RACSignal *)ySignal {
	return [[self.class pointsWithX:self.x Y:ySignal] setNameWithFormat:@"[%@] -replaceY: %@", self.name, ySignal];
}

- (RACSignal *)valueForAttribute:(NSLayoutAttribute)attribute {
	return [combineAttributeAndSignals(attribute, @[ self ], ^ id (NSNumber *edge, NSValue *value) {
		NSAssert([value isKindOfClass:NSValue.class] && value.med_geometryStructType == MEDGeometryStructTypeRect, @"Value sent by %@ is not a CGRect: %@", self, value);

		CGRect rect = value.med_rectValue;
		if (edge == nil) {
			switch (attribute) {
				case NSLayoutAttributeWidth:
					return @(CGRectGetWidth(rect));

				case NSLayoutAttributeHeight:
					return @(CGRectGetHeight(rect));

				case NSLayoutAttributeCenterX:
					return @(CGRectGetMidX(rect));

				case NSLayoutAttributeCenterY:
					return @(CGRectGetMidY(rect));

				default:
					NSAssert(NO, @"NSLayoutAttribute should have had a CGRectEdge: %li", (long)attribute);
					return nil;
			}
		} else {
			switch (edge.unsignedIntegerValue) {
				case CGRectMinXEdge:
					return @(CGRectGetMinX(rect));

				case CGRectMaxXEdge:
					return @(CGRectGetMaxX(rect));

				case CGRectMinYEdge:
					return @(CGRectGetMinY(rect));

				case CGRectMaxYEdge:
					return @(CGRectGetMaxY(rect));

				default:
					NSAssert(NO, @"Unrecognized CGRectEdge: %@", edge);
					return nil;
			}
		}
	}) setNameWithFormat:@"[%@] -valueForAttribute: %li", self.name, (long)attribute];
}

- (RACSignal *)left {
	return [[self valueForAttribute:NSLayoutAttributeLeft] setNameWithFormat:@"[%@] -left", self.name];
}

- (RACSignal *)right {
	return [[self valueForAttribute:NSLayoutAttributeRight] setNameWithFormat:@"[%@] -right", self.name];
}

- (RACSignal *)top {
	return [[self valueForAttribute:NSLayoutAttributeTop] setNameWithFormat:@"[%@] -top", self.name];
}

- (RACSignal *)bottom {
	return [[self valueForAttribute:NSLayoutAttributeBottom] setNameWithFormat:@"[%@] -bottom", self.name];
}

- (RACSignal *)leading {
	return [[self valueForAttribute:NSLayoutAttributeLeading] setNameWithFormat:@"[%@] -leading", self.name];
}

- (RACSignal *)trailing {
	return [[self valueForAttribute:NSLayoutAttributeTrailing] setNameWithFormat:@"[%@] -trailing", self.name];
}

- (RACSignal *)centerX {
	return [[self valueForAttribute:NSLayoutAttributeCenterX] setNameWithFormat:@"[%@] -centerX", self.name];
}

- (RACSignal *)centerY {
	return [[self valueForAttribute:NSLayoutAttributeCenterY] setNameWithFormat:@"[%@] -centerY", self.name];
}

- (RACSignal *)alignAttribute:(NSLayoutAttribute)attribute to:(RACSignal *)valueSignal {
	NSParameterAssert(valueSignal != nil);

	return [combineAttributeAndSignals(attribute, @[ valueSignal, self ], ^ id (NSNumber *edge, NSNumber *num, NSValue *value) {
		NSAssert([num isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", valueSignal, num);
		NSAssert([value isKindOfClass:NSValue.class] && value.med_geometryStructType == MEDGeometryStructTypeRect, @"Value sent by %@ is not a CGRect: %@", self, value);

		CGFloat n = num.doubleValue;
		CGRect rect = value.med_rectValue;

		if (edge == nil) {
			switch (attribute) {
				case NSLayoutAttributeWidth:
					rect.size.width = n;
					break;

				case NSLayoutAttributeHeight:
					rect.size.height = n;
					break;

				case NSLayoutAttributeCenterX:
					rect.origin.x = n - CGRectGetWidth(rect) / 2;
					break;

				case NSLayoutAttributeCenterY:
					rect.origin.y = n - CGRectGetHeight(rect) / 2;
					break;

				default:
					NSAssert(NO, @"NSLayoutAttribute should have had a CGRectEdge: %li", (long)attribute);
					return nil;
			}
		} else {
			switch (edge.unsignedIntegerValue) {
				case CGRectMinXEdge:
					rect.origin.x = n;
					break;

				case CGRectMinYEdge:
					rect.origin.y = n;
					break;

				case CGRectMaxXEdge:
					rect.origin.x = n - CGRectGetWidth(rect);
					break;

				case CGRectMaxYEdge:
					rect.origin.y = n - CGRectGetHeight(rect);
					break;

				default:
					NSAssert(NO, @"Unrecognized CGRectEdge: %@", edge);
					return nil;
			}
		}

		return MEDBox(CGRectStandardize(rect));
	}) setNameWithFormat:@"[%@] -alignAttribute: %li to: %@", self.name, (long)attribute, valueSignal];
}

- (RACSignal *)alignCenter:(RACSignal *)centerSignal {
	NSParameterAssert(centerSignal != nil);

	return [[RACSignal combineLatest:@[ centerSignal, self ] reduce:^(NSValue *center, NSValue *value) {
		NSAssert([center isKindOfClass:NSValue.class] && center.med_geometryStructType == MEDGeometryStructTypePoint, @"Value sent by %@ is not a CGPoint: %@", centerSignal, center);
		NSAssert([value isKindOfClass:NSValue.class] && value.med_geometryStructType == MEDGeometryStructTypeRect, @"Value sent by %@ is not a CGRect: %@", self, value);

		CGFloat x = center.med_pointValue.x;
		CGFloat y = center.med_pointValue.y;

		CGRect rect = value.med_rectValue;
		return MEDBox(CGRectMake(x - CGRectGetWidth(rect) / 2, y - CGRectGetHeight(rect) / 2, CGRectGetWidth(rect), CGRectGetHeight(rect)));
	}] setNameWithFormat:@"[%@] -alignCenter: %@", self.name, centerSignal];
}

- (RACSignal *)alignLeft:(RACSignal *)positionSignal {
	return [[self alignAttribute:NSLayoutAttributeLeft to:positionSignal] setNameWithFormat:@"[%@] -alignLeft: %@", self.name, positionSignal];
}

- (RACSignal *)alignRight:(RACSignal *)positionSignal {
	return [[self alignAttribute:NSLayoutAttributeRight to:positionSignal] setNameWithFormat:@"[%@] -alignRight: %@", self.name, positionSignal];
}

- (RACSignal *)alignTop:(RACSignal *)positionSignal {
	return [[self alignAttribute:NSLayoutAttributeTop to:positionSignal] setNameWithFormat:@"[%@] -alignTop: %@", self.name, positionSignal];
}

- (RACSignal *)alignBottom:(RACSignal *)positionSignal {
	return [[self alignAttribute:NSLayoutAttributeBottom to:positionSignal] setNameWithFormat:@"[%@] -alignBottom: %@", self.name, positionSignal];
}

- (RACSignal *)alignLeading:(RACSignal *)positionSignal {
	return [[self alignAttribute:NSLayoutAttributeLeading to:positionSignal] setNameWithFormat:@"[%@] -alignLeading: %@", self.name, positionSignal];
}

- (RACSignal *)alignTrailing:(RACSignal *)positionSignal {
	return [[self alignAttribute:NSLayoutAttributeTrailing to:positionSignal] setNameWithFormat:@"[%@] -alignTrailing: %@", self.name, positionSignal];
}

- (RACSignal *)alignWidth:(RACSignal *)amountSignal {
	return [[self alignAttribute:NSLayoutAttributeWidth to:amountSignal] setNameWithFormat:@"[%@] -alignWidth: %@", self.name, amountSignal];
}

- (RACSignal *)alignHeight:(RACSignal *)amountSignal {
	return [[self alignAttribute:NSLayoutAttributeHeight to:amountSignal] setNameWithFormat:@"[%@] -alignHeight: %@", self.name, amountSignal];
}

- (RACSignal *)alignCenterX:(RACSignal *)positionSignal {
	return [[self alignAttribute:NSLayoutAttributeCenterX to:positionSignal] setNameWithFormat:@"[%@] -alignCenterX: %@", self.name, positionSignal];
}

- (RACSignal *)alignCenterY:(RACSignal *)positionSignal {
	return [[self alignAttribute:NSLayoutAttributeCenterY to:positionSignal] setNameWithFormat:@"[%@] -alignCenterY: %@", self.name, positionSignal];
}

- (RACSignal *)alignBaseline:(RACSignal *)baselineSignal toBaseline:(RACSignal *)referenceBaselineSignal ofRect:(RACSignal *)referenceRectSignal {
	NSParameterAssert(baselineSignal != nil);
	NSParameterAssert(referenceBaselineSignal != nil);
	NSParameterAssert(referenceRectSignal != nil);

	return [[RACSignal
		combineLatest:@[ referenceBaselineSignal, referenceRectSignal, baselineSignal, self ]
		reduce:^(NSNumber *referenceBaselineNum, NSValue *referenceRectValue, NSNumber *baselineNum, NSValue *rectValue) {
			NSAssert([referenceBaselineNum isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", referenceBaselineSignal, referenceBaselineNum);
			NSAssert([referenceRectValue isKindOfClass:NSValue.class] && referenceRectValue.med_geometryStructType == MEDGeometryStructTypeRect, @"Value sent by %@ is not a CGRect: %@", referenceRectSignal, referenceRectValue);
			NSAssert([baselineNum isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", baselineSignal, baselineNum);
			NSAssert([rectValue isKindOfClass:NSValue.class] && rectValue.med_geometryStructType == MEDGeometryStructTypeRect, @"Value sent by %@ is not a CGRect: %@", self, rectValue);

			CGRect rect = rectValue.med_rectValue;
			CGFloat baseline = baselineNum.doubleValue;

			CGRect referenceRect = referenceRectValue.med_rectValue;
			CGFloat referenceBaseline = referenceBaselineNum.doubleValue;

			#ifdef RCL_FOR_IPHONE
				// Flip the baselines so they're relative to a shared minY.
				baseline = CGRectGetHeight(rect) - baseline + CGRectGetMinY(rect);
				referenceBaseline = CGRectGetHeight(referenceRect) - referenceBaseline + CGRectGetMinY(referenceRect);

				rect = CGRectOffset(rect, 0, referenceBaseline - baseline);
			#else
				// Recalculate the baselines relative to a shared minY.
				baseline += CGRectGetMinY(rect);
				referenceBaseline += CGRectGetMinY(referenceRect);

				rect = CGRectOffset(rect, 0, referenceBaseline - baseline);
			#endif

			return MEDBox(rect);
		}]
		setNameWithFormat:@"[%@] -alignBaseline: %@ toBaseline: %@ ofRect: %@", self.name, baselineSignal, referenceBaselineSignal, referenceRectSignal];
}

- (RACSignal *)insetBy:(RACSignal *)insetSignal nullRect:(CGRect)nullRect {
	NSParameterAssert(insetSignal != nil);
	
	return [[RACSignal combineLatest:@[ insetSignal, self ] reduce:^(NSValue *insets, NSValue *rect) {
		NSAssert([insets isKindOfClass:NSValue.class] && insets.med_geometryStructType == MEDGeometryStructTypeEdgeInsets, @"Value sent by %@ is not an MEDEdgeInsets: %@", self, insets);
		NSAssert([rect isKindOfClass:NSValue.class] && rect.med_geometryStructType == MEDGeometryStructTypeRect, @"Value sent by %@ is not a CGRect: %@", self, rect);
		
		CGRect insetRect = MEDEdgeInsetsInsetRect(rect.med_rectValue, insets.med_edgeInsetsValue);
		if (CGRectIsNull(insetRect)) {
			return MEDBox(nullRect);
		} else {
			return MEDBox(insetRect);
		}
	}] setNameWithFormat:@"[%@] -inset: %@", self.name, insetSignal];
}

- (RACSignal *)insetWidth:(RACSignal *)widthSignal height:(RACSignal *)heightSignal nullRect:(CGRect)nullRect {
	NSParameterAssert(widthSignal != nil);
	NSParameterAssert(heightSignal != nil);

	RACSignal *insets = [RACSignal combineLatest:@[ widthSignal, heightSignal ] reduce:^(NSNumber *width, NSNumber *height) {
		NSAssert([width isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", widthSignal, width);
		NSAssert([height isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", heightSignal, height);
		
		CGFloat widthValue = width.doubleValue;
		CGFloat heightValue = height.doubleValue;
		return MEDBox(MEDEdgeInsetsMake(heightValue, widthValue, heightValue, widthValue));
	}];
	return [[self insetBy:insets nullRect:nullRect] setNameWithFormat:@"[%@] -insetWidth: %@ height: %@", self.name, widthSignal, heightSignal];
}

- (RACSignal *)insetTop:(RACSignal *)topSignal left:(RACSignal *)leftSignal bottom:(RACSignal *)bottomSignal right:(RACSignal *)rightSignal nullRect:(CGRect)nullRect {
	NSParameterAssert(topSignal != nil);
	NSParameterAssert(leftSignal != nil);
	NSParameterAssert(bottomSignal != nil);
	NSParameterAssert(rightSignal != nil);
	
	RACSignal *insets = [RACSignal combineLatest:@[ topSignal, leftSignal, bottomSignal, rightSignal ] reduce:^(NSNumber *top, NSNumber *left, NSNumber *bottom, NSNumber *right) {
		NSAssert([top isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", topSignal, top);
		NSAssert([left isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", leftSignal, left);
		NSAssert([bottom isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", bottomSignal, bottom);
		NSAssert([right isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", rightSignal, right);
		
		return MEDBox(MEDEdgeInsetsMake(top.doubleValue, left.doubleValue, bottom.doubleValue, right.doubleValue));
	}];
	return [[self insetBy:insets nullRect:nullRect] setNameWithFormat:@"[%@] -insetTop: %@ left: %@ bottom: %@ right: %@", self.name, topSignal, leftSignal, bottomSignal, rightSignal];
}

- (RACSignal *)offsetByAmount:(RACSignal *)amountSignal towardEdge:(NSLayoutAttribute)edgeAttribute {
	NSParameterAssert(amountSignal != nil);

	return [combineAttributeAndSignals(edgeAttribute, @[ amountSignal, self ], ^ id (NSNumber *edge, NSNumber *num, NSValue *value) {
		NSAssert(edge != nil, @"NSLayoutAttribute does not represent an edge: %li", (long)edgeAttribute);
		NSAssert([num isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", amountSignal, num);
		NSAssert([value isKindOfClass:NSValue.class], @"Value sent by %@ is not an NSValue: %@", self, value);

		CGFloat n = num.doubleValue;
		CGRect rect = CGRectZero;

		switch (value.med_geometryStructType) {
			case MEDGeometryStructTypeRect:
				rect = value.med_rectValue;
				break;

			case MEDGeometryStructTypePoint:
				rect.origin = value.med_pointValue;
				break;

			default:
				NSAssert(NO, @"Value sent by %@ is not a CGRect or CGPoint: %@", self, value);
		}

		switch (edge.unsignedIntegerValue) {
			case CGRectMinXEdge:
				rect.origin.x -= n;
				break;

			case CGRectMinYEdge:
				rect.origin.y -= n;
				break;

			case CGRectMaxXEdge:
				rect.origin.x += n;
				break;

			case CGRectMaxYEdge:
				rect.origin.y += n;
				break;

			default:
				NSAssert(NO, @"Unrecognized CGRectEdge: %@", edge);
				return nil;
		}

		if (value.med_geometryStructType == MEDGeometryStructTypePoint) {
			return MEDBox(rect.origin);
		} else {
			return MEDBox(CGRectStandardize(rect));
		}
	}) setNameWithFormat:@"[%@] -offsetByAmount: %@ towardEdge: %li", self.name, amountSignal, (long)edgeAttribute];
}

- (RACSignal *)moveLeft:(RACSignal *)amountSignal {
	return [[self offsetByAmount:amountSignal towardEdge:NSLayoutAttributeLeft] setNameWithFormat:@"[%@] -moveLeft: %@", self.name, amountSignal];
}

- (RACSignal *)moveRight:(RACSignal *)amountSignal {
	return [[self offsetByAmount:amountSignal towardEdge:NSLayoutAttributeRight] setNameWithFormat:@"[%@] -moveRight: %@", self.name, amountSignal];
}

- (RACSignal *)moveUp:(RACSignal *)amountSignal {
	return [[self offsetByAmount:amountSignal towardEdge:NSLayoutAttributeTop] setNameWithFormat:@"[%@] -moveUp: %@", self.name, amountSignal];
}

- (RACSignal *)moveDown:(RACSignal *)amountSignal {
	return [[self offsetByAmount:amountSignal towardEdge:NSLayoutAttributeBottom] setNameWithFormat:@"[%@] -moveDown: %@", self.name, amountSignal];
}

- (RACSignal *)moveLeadingOutward:(RACSignal *)amountSignal {
	return [[self offsetByAmount:amountSignal towardEdge:NSLayoutAttributeLeading] setNameWithFormat:@"[%@] -moveLeadingOutward: %@", self.name, amountSignal];
}

- (RACSignal *)moveTrailingOutward:(RACSignal *)amountSignal {
	return [[self offsetByAmount:amountSignal towardEdge:NSLayoutAttributeTrailing] setNameWithFormat:@"[%@] -moveTrailingOutward: %@", self.name, amountSignal];
}

- (RACSignal *)extendAttribute:(NSLayoutAttribute)attribute byAmount:(RACSignal *)amountSignal {
	NSParameterAssert(amountSignal != nil);

	return [combineAttributeAndSignals(attribute, @[ amountSignal, self ], ^ id (NSNumber *edge, NSNumber *amount, NSValue *value) {
		NSAssert([amount isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", amountSignal, amount);
		NSAssert([value isKindOfClass:NSValue.class] && value.med_geometryStructType == MEDGeometryStructTypeRect, @"Value sent by %@ is not a CGRect: %@", self, value);

		CGFloat n = amount.doubleValue;
		CGRect rect = value.med_rectValue;

		if (edge == nil) {
			switch (attribute) {
				case NSLayoutAttributeWidth:
					rect.size.width += n;
					rect.origin.x -= n / 2;
					break;

				case NSLayoutAttributeHeight:
					rect.size.height += n;
					rect.origin.y -= n / 2;
					break;

				default:
					NSAssert(NO, @"NSLayoutAttribute cannot be extended: %li", (long)attribute);
					return nil;
			}
		} else {
			rect = MEDRectGrow(rect, n, (CGRectEdge)edge.unsignedIntegerValue);
		}

		return MEDBox(CGRectStandardize(rect));
	}) setNameWithFormat:@"[%@] -extendAttribute: %li byAmount: %@", self.name, (long)attribute, amountSignal];
}

- (RACSignal *)sliceWithAmount:(RACSignal *)amountSignal fromEdge:(NSLayoutAttribute)edgeAttribute {
	return [[self divideWithAmount:amountSignal fromEdge:edgeAttribute][0] setNameWithFormat:@"[%@] -sliceWithAmount: %@ fromEdge: %li", self.name, amountSignal, (long)edgeAttribute];
}

- (RACSignal *)remainderAfterSlicingAmount:(RACSignal *)amountSignal fromEdge:(NSLayoutAttribute)edgeAttribute {
	return [[self divideWithAmount:amountSignal fromEdge:edgeAttribute][1] setNameWithFormat:@"[%@] -remainderAfterSlicingAmount: %@ fromEdge: %li", self.name, amountSignal, (long)edgeAttribute];
}

- (RACTuple *)divideWithAmount:(RACSignal *)sliceAmountSignal fromEdge:(NSLayoutAttribute)edgeAttribute {
	return [self divideWithAmount:sliceAmountSignal padding:[RACSignal return:@0] fromEdge:edgeAttribute];
}

- (RACTuple *)divideWithAmount:(RACSignal *)amountSignal padding:(RACSignal *)paddingSignal fromEdge:(NSLayoutAttribute)edgeAttribute {
	NSParameterAssert(amountSignal != nil);
	NSParameterAssert(paddingSignal != nil);

	RACSignal *combinedSignal = combineAttributeAndSignals(edgeAttribute, @[ amountSignal, paddingSignal, self ], ^ id (NSNumber *edge, NSNumber *amount, NSNumber *padding, NSValue *value) {
		NSAssert(edge != nil, @"NSLayoutAttribute does not represent an edge: %li", (long)edgeAttribute);
		NSAssert([amount isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", amountSignal, amount);
		NSAssert([padding isKindOfClass:NSNumber.class], @"Value sent by %@ is not a number: %@", paddingSignal, padding);
		NSAssert([value isKindOfClass:NSValue.class] && value.med_geometryStructType == MEDGeometryStructTypeRect, @"Value sent by %@ is not a CGRect: %@", self, value);

		CGRect rect = value.med_rectValue;

		CGRect slice = CGRectZero;
		CGRect remainder = CGRectZero;
		MEDRectDivideWithPadding(rect, &slice, &remainder, amount.doubleValue, padding.doubleValue, (CGRectEdge)edge.unsignedIntegerValue);

		return [RACTuple tupleWithObjects:MEDBox(slice), MEDBox(remainder), nil];
	});

	NSString *invocationName = [NSString stringWithFormat:@"-divideWithAmount: %@ padding: %@ fromEdge: %li", amountSignal, paddingSignal, (long)edgeAttribute];

	// Now, convert Signal[(Rect, Rect)] into (Signal[Rect], Signal[Rect]).
	RACSignal *sliceSignal = [[combinedSignal map:^(RACTuple *tuple) {
		return tuple[0];
	}] setNameWithFormat:@"[%@] SLICE OF %@", self.name, invocationName];

	RACSignal *remainderSignal = [[combinedSignal map:^(RACTuple *tuple) {
		return tuple[1];
	}] setNameWithFormat:@"[%@] REMAINDER OF %@", self.name, invocationName];

	return [RACTuple tupleWithObjects:sliceSignal, remainderSignal, nil];
}

+ (RACSignal *)max:(NSArray *)signals {
	return [latestSortedNumber(signals, NO) setNameWithFormat:@"+max: %@", signals];
}

+ (RACSignal *)min:(NSArray *)signals {
	return [latestSortedNumber(signals, YES) setNameWithFormat:@"+min: %@", signals];
}

+ (RACSignal *)add:(NSArray *)signals {
	return [combineSignalsWithOperator(signals, ^(CGFloat a, CGFloat b) {
		return a + b;
	}) setNameWithFormat:@"+add: %@", signals];
}

+ (RACSignal *)subtract:(NSArray *)signals {
	return [combineSignalsWithOperator(signals, ^(CGFloat a, CGFloat b) {
		return a - b;
	}) setNameWithFormat:@"+subtract: %@", signals];
}

+ (RACSignal *)multiply:(NSArray *)signals {
	return [combineSignalsWithOperator(signals, ^(CGFloat a, CGFloat b) {
		return a * b;
	}) setNameWithFormat:@"+multiply: %@", signals];
}

+ (RACSignal *)divide:(NSArray *)signals {
	return [combineSignalsWithOperator(signals, ^(CGFloat a, CGFloat b) {
		return a / b;
	}) setNameWithFormat:@"+divide: %@", signals];
}

- (RACSignal *)plus:(RACSignal *)addendSignal {
	NSParameterAssert(addendSignal != nil);

	return [combineSignalsWithOperator(@[ self, addendSignal ], ^(CGFloat a, CGFloat b) {
		return a + b;
	}) setNameWithFormat:@"[%@] -plus: %@", self, addendSignal];
}

- (RACSignal *)minus:(RACSignal *)subtrahendSignal {
	NSParameterAssert(subtrahendSignal != nil);

	return [combineSignalsWithOperator(@[ self, subtrahendSignal ], ^(CGFloat a, CGFloat b) {
		return a - b;
	}) setNameWithFormat:@"[%@] -minus: %@", self, subtrahendSignal];
}

- (RACSignal *)multipliedBy:(RACSignal *)factorSignal {
	NSParameterAssert(factorSignal != nil);

	return [combineSignalsWithOperator(@[ self, factorSignal ], ^(CGFloat a, CGFloat b) {
		return a * b;
	}) setNameWithFormat:@"[%@] -multipliedBy: %@", self, factorSignal];
}

- (RACSignal *)dividedBy:(RACSignal *)denominatorSignal {
	NSParameterAssert(denominatorSignal != nil);

	return [combineSignalsWithOperator(@[ self, denominatorSignal ], ^(CGFloat a, CGFloat b) {
		return a / b;
	}) setNameWithFormat:@"[%@] -dividedBy: %@", self, denominatorSignal];
}

- (RACSignal *)negate {
	return [[self map:^ id (id value) {
		if ([value isKindOfClass:NSNumber.class]) {
			return @(-[value doubleValue]);
		}

		NSAssert([value isKindOfClass:NSValue.class], @"Expected a number or value, got %@", value);

		switch ([value med_geometryStructType]) {
			case MEDGeometryStructTypeRect: {
				CGRect rect = [value med_rectValue];
				rect.origin.x *= -1;
				rect.origin.y *= -1;
				rect.size.width *= -1;
				rect.size.height *= -1;
				return MEDBox(CGRectStandardize(rect));
			}

			case MEDGeometryStructTypePoint: {
				CGPoint point = [value med_pointValue];
				point.x *= -1;
				point.y *= -1;
				return MEDBox(point);
			}

			case MEDGeometryStructTypeSize: {
				CGSize size = [value med_sizeValue];
				size.width *= -1;
				size.height *= -1;
				return MEDBox(size);
			}

			default:
				NSAssert(NO, @"Unsupported type of value to negate: %@", value);
				return nil;
		}
	}] setNameWithFormat:@"[%@] -negate", self.name];
}

- (RACSignal *)floor {
	return [[self map:^ id (id value) {
		if ([value isKindOfClass:NSNumber.class]) {
			return @(floor([value doubleValue]));
		}

		NSAssert([value isKindOfClass:NSValue.class], @"Expected a number or value, got %@", value);

		switch ([value med_geometryStructType]) {
			case MEDGeometryStructTypeRect:
				return MEDBox(MEDRectFloor([value med_rectValue]));

			case MEDGeometryStructTypePoint:
				return MEDBox(MEDPointFloor([value med_pointValue]));

			case MEDGeometryStructTypeSize: {
				CGSize size = [value med_sizeValue];
				size.width = floor(size.width);
				size.height = floor(size.height);
				return MEDBox(size);
			}

			default:
				NSAssert(NO, @"Unsupported type of value to floor: %@", value);
				return nil;
		}
	}] setNameWithFormat:@"[%@] -floor", self.name];
}

- (RACSignal *)ceil {
	return [[self map:^ id (id value) {
		if ([value isKindOfClass:NSNumber.class]) {
			return @(ceil([value doubleValue]));
		}

		NSAssert([value isKindOfClass:NSValue.class], @"Expected a number or value, got %@", value);

		switch ([value med_geometryStructType]) {
			case MEDGeometryStructTypeRect:
				return MEDBox(CGRectIntegral([value med_rectValue]));

			case MEDGeometryStructTypePoint: {
				CGPoint point = [value med_pointValue];
				point.x = floor(point.x);
				point.y = floor(point.y);
				return MEDBox(point);
			}

			case MEDGeometryStructTypeSize: {
				CGSize size = [value med_sizeValue];
				size.width = ceil(size.width);
				size.height = ceil(size.height);
				return MEDBox(size);
			}

			default:
				NSAssert(NO, @"Unsupported type of value to ceil: %@", value);
				return nil;
		}
	}] setNameWithFormat:@"[%@] -ceil", self.name];
}

@end
