//
//  TestView.m
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-17.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "TestView.h"

@interface TestView ()

@property (nonatomic, assign) CGSize size;
@property (nonatomic, strong) id baselineView;

@end

@implementation TestView

#pragma mark UIView and NSView

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self == nil) return nil;

	_baselineView = [[self.superclass alloc] initWithFrame:CGRectZero];
	[self addSubview:self.baselineView];

	#ifdef RCL_FOR_IPHONE
	[self.baselineView setAutoresizingMask:UIViewAutoresizingFlexibleTopMargin];
	#else
	[(NSView *)self.baselineView setAutoresizingMask:NSViewMaxYMargin];
	#endif

	self.baselineOffsetFromBottom = 0;

	return self;
}

#ifdef RCL_FOR_IPHONE
- (UIView *)viewForBaselineLayout {
	return self.baselineView;
}
#else
- (CGFloat)baselineOffsetFromBottom {
	return CGRectGetMinY([self.baselineView frame]);
}
#endif

#pragma mark Test API

- (void)invalidateAndSetIntrinsicContentSize:(CGSize)size {
	self.size = size;
	[self invalidateIntrinsicContentSize];
}

#pragma mark Auto Layout

- (CGRect)alignmentRectForFrame:(CGRect)frame {
	return CGRectInset(frame, 1, 2);
}

- (CGRect)frameForAlignmentRect:(CGRect)rect {
	return CGRectInset(rect, -1, -2);
}

- (CGSize)intrinsicContentSize {
	return self.size;
}

- (void)setBaselineOffsetFromBottom:(CGFloat)baseline {
	#ifdef RCL_FOR_IPHONE
	CGRect frame = CGRectMake(0, CGRectGetHeight(self.bounds) - baseline - 1, CGRectGetWidth(self.bounds), 1);
	#else
	CGRect frame = CGRectMake(0, baseline, CGRectGetWidth(self.bounds), 1);
	#endif

	[self.baselineView setFrame:frame];
}

@end
