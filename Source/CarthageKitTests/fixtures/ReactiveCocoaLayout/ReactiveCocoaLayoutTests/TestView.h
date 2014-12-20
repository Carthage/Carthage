//
//  TestView.h
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-17.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#ifdef RCL_FOR_IPHONE
#import <UIKit/UIKit.h>

@interface TestView : UIView

#else
#import <AppKit/AppKit.h>

@interface TestView : NSView

#endif

// Insets the given frame by 1 point horizontally and 2 points vertically.
- (CGRect)alignmentRectForFrame:(CGRect)frame;

- (void)invalidateAndSetIntrinsicContentSize:(CGSize)size;
- (void)setBaselineOffsetFromBottom:(CGFloat)baseline;

@end
