//
//  MEDNSValueAdditionsSpec.m
//  Archimedes
//
//  Created by Justin Spahr-Summers on 2012-12-12.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import <Archimedes/Archimedes.h>
#import <Nimble/Nimble.h>
#import <Quick/Quick.h>

QuickSpecBegin(NSValueAdditions)

CGRect rect = CGRectMake(10, 20, 30, 40);
CGPoint point = CGPointMake(100, 200);
CGSize size = CGSizeMake(300, 400);
MEDEdgeInsets insets = MEDEdgeInsetsMake(1, 2, 3, 4);

__block NSValue *rectValue;
__block NSValue *pointValue;
__block NSValue *sizeValue;
__block NSValue *insetsValue;

qck_beforeEach(^{
	rectValue = [NSValue med_valueWithRect:rect];
	expect(rectValue).notTo(beNil());

	pointValue = [NSValue med_valueWithPoint:point];
	expect(pointValue).notTo(beNil());

	sizeValue = [NSValue med_valueWithSize:size];
	expect(sizeValue).notTo(beNil());

	insetsValue = [NSValue med_valueWithEdgeInsets:insets];
	expect(insetsValue).notTo(beNil());
});

qck_it(@"should wrap a CGRect", ^{
	expect(@(CGRectEqualToRect(rectValue.med_rectValue, rect))).to(beTruthy());
});

qck_it(@"should wrap a CGPoint", ^{
	expect(@(CGPointEqualToPoint(pointValue.med_pointValue, point))).to(beTruthy());
});

qck_it(@"should wrap a CGSize", ^{
	expect(@(CGSizeEqualToSize(sizeValue.med_sizeValue, size))).to(beTruthy());
});

qck_it(@"should wrap an MEDEdgeInsets", ^{
	expect(@(MEDEdgeInsetsEqualToEdgeInsets(insetsValue.med_edgeInsetsValue, insets))).to(beTruthy());
});

qck_describe(@"MEDBox", ^{
	qck_it(@"should wrap a CGRect", ^{
		NSValue *value = MEDBox(rect);
		expect(value).to(equal(rectValue));
	});

	qck_it(@"should wrap a CGPoint", ^{
		NSValue *value = MEDBox(point);
		expect(value).to(equal(pointValue));
	});

	qck_it(@"should wrap a CGSize", ^{
		NSValue *value = MEDBox(size);
		expect(value).to(equal(sizeValue));
	});

	qck_it(@"should wrap a MEDEdgeInsets", ^{
		NSValue *value = MEDBox(insets);
		expect(value).to(equal(insetsValue));
	});

	// Specifically used because we don't support it directly.
	qck_it(@"should wrap a CGAffineTransform", ^{
		CGAffineTransform transform = CGAffineTransformMake(1, 2, 5, 8, 13, 21);

		NSValue *value = MEDBox(transform);
		expect(value).notTo(beNil());

		CGAffineTransform readTransform;
		[value getValue:&readTransform];

		expect(@(CGAffineTransformEqualToTransform(transform, readTransform))).to(beTruthy());
	});
});

qck_describe(@"med_geometryStructType", ^{
	qck_it(@"should identify a CGRect", ^{
		expect(@(rectValue.med_geometryStructType)).to(equal(@(MEDGeometryStructTypeRect)));
	});

	qck_it(@"should identify a CGPoint", ^{
		expect(@(pointValue.med_geometryStructType)).to(equal(@(MEDGeometryStructTypePoint)));
	});

	qck_it(@"should identify a CGSize", ^{
		expect(@(sizeValue.med_geometryStructType)).to(equal(@(MEDGeometryStructTypeSize)));
	});

	qck_it(@"should identify an MEDEdgeInsets", ^{
		expect(@(insetsValue.med_geometryStructType)).to(equal(@(MEDGeometryStructTypeEdgeInsets)));
	});

	qck_it(@"should return MEDGeometryStructTypeUnknown for unknown types", ^{
		NSNumber *num = @5;
		expect(@(num.med_geometryStructType)).to(equal(@(MEDGeometryStructTypeUnknown)));
	});
});

QuickSpecEnd
