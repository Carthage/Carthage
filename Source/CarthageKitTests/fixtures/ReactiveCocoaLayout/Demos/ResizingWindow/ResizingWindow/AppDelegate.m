//
//  AppDelegate.m
//  ResizingWindow
//
//  Created by Justin Spahr-Summers on 2012-12-12.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "AppDelegate.h"
#import "ResizingWindowController.h"

@interface AppDelegate ()

@property (nonatomic, strong) ResizingWindowController *mainWindowController;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	self.mainWindowController = [[ResizingWindowController alloc] init];
	[self.mainWindowController showWindow:self];
}

@end
