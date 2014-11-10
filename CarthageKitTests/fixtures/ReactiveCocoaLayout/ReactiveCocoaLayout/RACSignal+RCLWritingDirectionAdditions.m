//
//  RACSignal+RCLWritingDirectionAdditions.m
//  ReactiveCocoaLayout
//
//  Created by Justin Spahr-Summers on 2012-12-18.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "RACSignal+RCLWritingDirectionAdditions.h"

// Returns a signal which sends the character direction for the current language,
// and automatically re-sends it any time the current locale changes.
static RACSignal *characterDirectionSignal(void) {
	return [[[[NSNotificationCenter.defaultCenter rac_addObserverForName:NSCurrentLocaleDidChangeNotification object:nil]
		startWith:nil]
		map:^(id _) {
			NSArray *preferredLanguages = NSLocale.preferredLanguages;
			return (preferredLanguages.count > 0 ? preferredLanguages[0] : [NSLocale.currentLocale objectForKey:NSLocaleLanguageCode]);
		}]
		map:^(NSString *languageCode) {
			return @([NSLocale characterDirectionForLanguage:languageCode]);
		}];
}

@implementation RACSignal (RCLWritingDirectionAdditions)

+ (RACSignal *)leadingEdgeSignal {
	return [[characterDirectionSignal() map:^(NSNumber *direction) {
		if (direction.unsignedIntegerValue == NSLocaleLanguageDirectionRightToLeft) {
			return @(CGRectMaxXEdge);
		} else {
			return @(CGRectMinXEdge);
		}
	}] setNameWithFormat:@"+leadingEdgeSignal"];
}

+ (RACSignal *)trailingEdgeSignal {
	return [[characterDirectionSignal() map:^(NSNumber *direction) {
		if (direction.unsignedIntegerValue == NSLocaleLanguageDirectionRightToLeft) {
			return @(CGRectMinXEdge);
		} else {
			return @(CGRectMaxXEdge);
		}
	}] setNameWithFormat:@"+trailingEdgeSignal"];
}

@end
