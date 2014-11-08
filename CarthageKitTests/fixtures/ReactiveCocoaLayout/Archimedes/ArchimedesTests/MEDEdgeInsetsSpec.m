//
//  MEDEdgeInsetsSpec.m
//  Archimedes
//
//  Created by Indragie Karunaratne on 8/6/2013.
//  Copyright (c) 2013 GitHub. All rights reserved.
//

#import <Archimedes/Archimedes.h>
#import <Nimble/Nimble.h>
#import <Quick/Quick.h>

static const MEDEdgeInsets insets = (MEDEdgeInsets){ .top = 1, .left = 2, .bottom = 3, .right = 4 };
static const MEDEdgeInsets insets2 = (MEDEdgeInsets){ .top = 1.05f, .left = 2.05f, .bottom = 3.05f, .right = 4.05f };

QuickSpecBegin(EdgeInsets)

qck_it(@"should check equality between MEDEdgeInsets", ^{
	MEDEdgeInsets insets3 = MEDEdgeInsetsMake(5, 6, 7, 8);
	expect(@(MEDEdgeInsetsEqualToEdgeInsets(insets, insets))).to(beTruthy());
	expect(@(MEDEdgeInsetsEqualToEdgeInsets(insets, insets2))).to(beTruthy());
	expect(@(MEDEdgeInsetsEqualToEdgeInsets(insets, insets3))).to(beFalsy());
});

qck_it(@"should make an MEDEdgeInsets", ^{
	MEDEdgeInsets newInsets = MEDEdgeInsetsMake(1, 2, 3, 4);
	expect(MEDBox(newInsets)).to(equal(MEDBox(insets)));
});

qck_it(@"should inset a CGRect", ^{
	CGRect rect = CGRectMake(10, 10, 10, 10);
#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
	CGRect insetRect = CGRectMake(12, 11, 4, 6);
#elif TARGET_OS_MAC
	CGRect insetRect = CGRectMake(12, 13, 4, 6);
#endif

	expect(MEDBox(MEDEdgeInsetsInsetRect(rect, insets))).to(equal(MEDBox(insetRect)));
});

qck_it(@"should create a string from an MEDEdgeInsets", ^{
	expect(NSStringFromMEDEdgeInsets(insets)).to(equal(@"{1, 2, 3, 4}"));
	expect(NSStringFromMEDEdgeInsets(insets2)).to(equal(@"{1.05, 2.05, 3.05, 4.05}"));
});

qck_it(@"should create an MEDEdgeInsets from a string", ^{
	expect(MEDBox(MEDEdgeInsetsFromString(@"{1, 2, 3, 4}"))).to(equal(MEDBox(insets)));
	expect(@(MEDEdgeInsetsEqualToEdgeInsets(MEDEdgeInsetsFromString(@"{1.05, 2.05, 3.05, 4.05}"), insets2))).to(beTruthy());
});

QuickSpecEnd
