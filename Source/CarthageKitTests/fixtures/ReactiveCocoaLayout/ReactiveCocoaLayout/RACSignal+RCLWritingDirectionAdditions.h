//
//  RACSignal+RCLWritingDirectionAdditions.h
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-18.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import <ReactiveCocoa/ReactiveCocoa.h>

@interface RACSignal (RCLWritingDirectionAdditions)

// Sends the side from which text begins in the user's locale. The signal will
// automatically re-send when the locale is changed.
//
// In a left-to-right language (such as English), this would be the left side.
//
// Returns a signal of NSNumber-boxed CGRectEdge values.
+ (RACSignal *)leadingEdgeSignal;

// Sends the side at which text ends in the user's locale. The signal will
// automatically re-send when the locale is changed.
//
// In a left-to-right language (such as English), this would be the right side.
//
// Returns a signal of NSNumber-boxed CGRectEdge values.
+ (RACSignal *)trailingEdgeSignal;

@end
