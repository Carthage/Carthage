//
//  ReactiveCocoaLayout.h
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-12.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import <Foundation/Foundation.h>

//! Project version number for ReactiveCocoaLayout.
FOUNDATION_EXPORT double ReactiveCocoaLayoutVersionNumber;

//! Project version string for ReactiveCocoaLayout.
FOUNDATION_EXPORT const unsigned char ReactiveCocoaLayoutVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <ReactiveCocoaLayout/PublicHeader.h>

#import <ReactiveCocoaLayout/RACSignal+RCLAnimationAdditions.h>
#import <ReactiveCocoaLayout/RACSignal+RCLGeometryAdditions.h>
#import <ReactiveCocoaLayout/RACSignal+RCLWritingDirectionAdditions.h>
#import <ReactiveCocoaLayout/RCLMacros.h>
#import <ReactiveCocoaLayout/View+RCLAutoLayoutAdditions.h>

#ifdef RCL_FOR_IPHONE
	#import <ReactiveCocoaLayout/UIView+RCLGeometryAdditions.h>
#else
	#import <ReactiveCocoaLayout/NSCell+RCLGeometryAdditions.h>
	#import <ReactiveCocoaLayout/NSControl+RCLGeometryAdditions.h>
	#import <ReactiveCocoaLayout/NSView+RCLGeometryAdditions.h>
#endif
