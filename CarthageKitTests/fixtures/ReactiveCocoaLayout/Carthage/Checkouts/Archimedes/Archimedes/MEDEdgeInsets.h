//
//  MEDEdgeInsets.h
//  Archimedes
//
//  Created by Indragie Karunaratne on 8/6/2013.
//  Copyright (c) 2013 GitHub. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
#import <UIKit/UIKit.h>
typedef UIEdgeInsets MEDEdgeInsets;
#elif TARGET_OS_MAC
#import <AppKit/AppKit.h>
typedef NSEdgeInsets MEDEdgeInsets;
#endif

// `MEDEdgeInsets` structure with all members set to 0.
#define MEDEdgeInsetsZero (MEDEdgeInsets){ .top = 0, .left = 0, .bottom = 0, .right = 0 }

// Returns an MEDEgeInsets struct with the given edge insets.
MEDEdgeInsets MEDEdgeInsetsMake(CGFloat top, CGFloat left, CGFloat bottom, CGFloat right);

// Returns whether the two given `MEDEdgeInsets` are equal.
BOOL MEDEdgeInsetsEqualToEdgeInsets(MEDEdgeInsets insets1, MEDEdgeInsets insets2);

// The top inset will affect the min Y coordinate on iOS, and max Y coordinate on
// OS X, and vice-versa for bottom due to the default flippedness of drawing contexts
// on each platform.
//
// Returns a rectangle adjusted by incrementing the origin and decrementing the size
// of the given rect by applying the given insets.
CGRect MEDEdgeInsetsInsetRect(CGRect rect, MEDEdgeInsets insets);

// Returns a string formatted to contain data from an `MEDEdgeInsets` structure.
//
// This string can be passed into `MEDEdgeInsetsFromString()` to recreate the original
// `MEDEdgeInsets` structure.
NSString * NSStringFromMEDEdgeInsets(MEDEdgeInsets insets);

// Returns an `MEDEdgeInsets` structure corresponding to data in the given string
// or `MEDEdgeInsetsZero` if the string is not formatted appropriately.
//
// The string format is “{top, left, bottom, right}”, where each member of the
// `MEDEdgeInsets` structure is separated with a comma. This function should generally
// only be used to convert strings that were previously created using the
// `NSStringFromMEDEdgeInsets()` function.
MEDEdgeInsets MEDEdgeInsetsFromString(NSString *string);
