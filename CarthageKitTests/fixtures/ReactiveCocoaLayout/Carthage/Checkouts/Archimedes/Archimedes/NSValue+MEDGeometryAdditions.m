//
//  NSValue+MEDGeometryAdditions.m
//  Archimedes
//
//  Created by Justin Spahr-Summers on 2012-12-12.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "NSValue+MEDGeometryAdditions.h"

#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
	#import <UIKit/UIKit.h>
#elif TARGET_OS_MAC
	#import <AppKit/AppKit.h>
#endif

@implementation NSValue (MEDGeometryAdditions)

#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED

+ (NSValue *)med_valueWithRect:(CGRect)rect {
	return [self valueWithCGRect:rect];
}

+ (NSValue *)med_valueWithPoint:(CGPoint)point {
	return [self valueWithCGPoint:point];
}

+ (NSValue *)med_valueWithSize:(CGSize)size {
	return [self valueWithCGSize:size];
}

+ (NSValue *)med_valueWithEdgeInsets:(MEDEdgeInsets)insets {
	return [self valueWithUIEdgeInsets:insets];
}

- (CGRect)med_rectValue {
	NSAssert(self.med_geometryStructType == MEDGeometryStructTypeRect, @"Value is not a CGRect: %@", self);
	return self.CGRectValue;
}

- (CGPoint)med_pointValue {
	NSAssert(self.med_geometryStructType == MEDGeometryStructTypePoint, @"Value is not a CGPoint: %@", self);
	return self.CGPointValue;
}

- (CGSize)med_sizeValue {
	NSAssert(self.med_geometryStructType == MEDGeometryStructTypeSize, @"Value is not a CGSize: %@", self);
	return self.CGSizeValue;
}

- (MEDEdgeInsets)med_edgeInsetsValue {
	NSAssert(self.med_geometryStructType == MEDGeometryStructTypeEdgeInsets, @"Value is not an MEDEdgeInsets: %@", self);
	return self.UIEdgeInsetsValue;
}

#elif TARGET_OS_MAC

+ (NSValue *)med_valueWithRect:(CGRect)rect {
	return [self valueWithRect:rect];
}

+ (NSValue *)med_valueWithPoint:(CGPoint)point {
	return [self valueWithPoint:point];
}

+ (NSValue *)med_valueWithSize:(CGSize)size {
	return [self valueWithSize:size];
}

+ (NSValue *)med_valueWithEdgeInsets:(MEDEdgeInsets)insets {
	return [self valueWithBytes:&insets objCType:@encode(MEDEdgeInsets)];
}

- (CGRect)med_rectValue {
	NSAssert(self.med_geometryStructType == MEDGeometryStructTypeRect, @"Value is not a CGRect: %@", self);
	return self.rectValue;
}

- (CGPoint)med_pointValue {
	NSAssert(self.med_geometryStructType == MEDGeometryStructTypePoint, @"Value is not a CGPoint: %@", self);
	return self.pointValue;
}

- (CGSize)med_sizeValue {
	NSAssert(self.med_geometryStructType == MEDGeometryStructTypeSize, @"Value is not a CGSize: %@", self);
	return self.sizeValue;
}

- (MEDEdgeInsets)med_edgeInsetsValue {
	NSAssert(self.med_geometryStructType == MEDGeometryStructTypeEdgeInsets, @"Value is not an MEDEdgeInsets: %@", self);
	MEDEdgeInsets insets;
	[self getValue:&insets];
	return insets;
}
#endif

- (MEDGeometryStructType)med_geometryStructType {
	const char *type = self.objCType;

	if (strcmp(type, @encode(CGRect)) == 0) {
		return MEDGeometryStructTypeRect;
	} else if (strcmp(type, @encode(CGPoint)) == 0) {
		return MEDGeometryStructTypePoint;
	} else if (strcmp(type, @encode(CGSize)) == 0) {
		return MEDGeometryStructTypeSize;
	} else if (strcmp(type, @encode(MEDEdgeInsets)) == 0) {
		return MEDGeometryStructTypeEdgeInsets;
	} else {
		return MEDGeometryStructTypeUnknown;
	}
}

@end
