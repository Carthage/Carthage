//
//  AppDelegate.swift
//  Scenester
//
//  Created by Brian Ivan Gesiak on 6/10/14.
//  Copyright (c) 2014 Brian Ivan Gesiak. All rights reserved.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet var window: NSWindow!
    
    func applicationShouldTerminateAfterLastWindowClosed(application: NSApplication) -> Bool {
        return true
    }
}
