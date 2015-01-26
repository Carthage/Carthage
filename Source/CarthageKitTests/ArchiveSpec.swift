//
//  ArchiveSpec.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2015-01-02.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import CarthageKit
import Foundation
import Nimble
import Quick
import ReactiveCocoa

class ArchiveSpec: QuickSpec {
	override func spec() {
		let archiveURL = NSBundle(forClass: self.dynamicType).URLForResource("CartfilePrivateOnly", withExtension: "zip")!

		it("should unzip archive to a temporary directory") {
			let result = unzipArchiveToTemporaryDirectory(archiveURL).single()
			expect(result.error()).to(beNil())

			let directoryPath = result.value()?.path ?? NSFileManager.defaultManager().currentDirectoryPath
			var isDirectory: ObjCBool = false
			expect(NSFileManager.defaultManager().fileExistsAtPath(directoryPath, isDirectory: &isDirectory)).to(beTruthy())
			expect(isDirectory).to(beTruthy())

			let contents = NSFileManager.defaultManager().contentsOfDirectoryAtPath(directoryPath, error: nil) ?? []
			let innerFolderName = "CartfilePrivateOnly"
			expect(contents.isEmpty).to(beFalsy())
			expect(contents).to(contain(innerFolderName))

			let innerContents = NSFileManager.defaultManager().contentsOfDirectoryAtPath(directoryPath.stringByAppendingPathComponent(innerFolderName), error: nil) ?? []
			expect(innerContents.isEmpty).to(beFalsy())
			expect(innerContents).to(contain("Cartfile.private"))
		}
	}
}
