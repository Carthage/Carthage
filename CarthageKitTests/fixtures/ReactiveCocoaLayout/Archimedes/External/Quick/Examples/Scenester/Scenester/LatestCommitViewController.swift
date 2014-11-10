//
//  LatestCommitViewController.swift
//  Scenester
//
//  Created by Brian Ivan Gesiak on 6/10/14.
//  Copyright (c) 2014 Brian Ivan Gesiak. All rights reserved.
//

import Cocoa

class LatestCommitViewController: NSViewController {
    @IBOutlet var button: NSButton!
    @IBOutlet var commitTextField: NSTextField!
    @IBOutlet var repoTextField: NSTextField!

    var requestingCommit: Bool {
        get { return !self.button.enabled }
        set { self.button.enabled = !newValue }
    }

    @IBAction func onRepoTextFieldEnter(NSTextField) {
        getLatestCommit()
    }

    @IBAction func onGetLatestCommitButtonClick(NSButton) {
        getLatestCommit()
    }

    func getLatestCommit() {
        if requestingCommit {
           return
        }

        let repo = self.repoTextField.stringValue

        if repo.isEmpty {
            let alert = NSAlert()
            alert.messageText = "You must input an :owner/:repo pair."
            alert.beginSheetModalForWindow(self.view.window, completionHandler: {(NSModalResponse) -> () in
                self.commitTextField.stringValue = ""
                })
            return
        }

        requestingCommit = true
        Commit.latestCommit(repo,
            success: { (commit: Commit) -> () in
                self.requestingCommit = false
                self.commitTextField.stringValue = commit.simpleDescription
            }, failure: {(error: NSError) -> () in
                self.requestingCommit = false
                let alert = NSAlert(error: error)
                alert.beginSheetModalForWindow(self.view.window,
                    completionHandler: {(NSModalResponse) -> () in
                        self.commitTextField.stringValue = ""
                    })
        })
    }
}