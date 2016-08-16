//
//  VersionFile.swift
//  Carthage
//
//  Created by Jason Boyle on 8/11/16.
//  Copyright © 2016 Carthage. All rights reserved.
//

import Foundation
import Argo
import Curry
import CryptoSwift

public struct VersionFile {
	public let commitish: String
	public let buildProductSHA1: String
	
	public static let commitishKeyName = "commitish"
	public static let buildProductSHA1KeyName = "buildProductSHA1"
	
	public init(commitish: String, buildProductSHA1: String) {
		self.commitish = commitish
		self.buildProductSHA1 = buildProductSHA1
	}
}

extension VersionFile: Decodable {
	public static func decode(j: JSON) -> Decoded<VersionFile> {
		return curry(self.init)
			<^> j <| VersionFile.commitishKeyName
			<*> j <| VersionFile.buildProductSHA1KeyName
	}
}

public extension VersionFile {
	public static func versionFileMatchesDependency(dependency: Dependency<PinnedVersion>, folderURL: NSURL) -> Bool {
		guard let versionFile = VersionFile.readVersionFileForProjectNamed(dependency.project.name, folderURL: folderURL) else {
			return false
		}
		
		guard versionFile.commitish == dependency.version.commitish else {
			return false
		}
		
		guard let frameworkFileURL = VersionFile.frameworkFileURL(folderURL, projectName: dependency.project.name) else {
			return false
		}
		
		guard let sha1 = VersionFile.sha1ForFileAtURL(frameworkFileURL) where versionFile.buildProductSHA1 == sha1 else {
			return false
		}
		
		return true
	}
	
	public static func createVersionFileForDependency(dependency: Dependency<PinnedVersion>, folderURL: NSURL) -> Bool {
		guard let frameworkFileURL = VersionFile.frameworkFileURL(folderURL, projectName: dependency.project.name) else {
			return false
		}
		
		guard let buildProductSHA1 = VersionFile.sha1ForFileAtURL(frameworkFileURL) else {
			return false
		}
		
		return VersionFile.createVersionFileForProjectNamed(dependency.project.name, commitish: dependency.version.commitish, buildProductSHA1: buildProductSHA1, folderURL: folderURL)
	}
	
	public static func createVersionFileForProjectNamed(projectName: String, commitish: String, buildProductSHA1: String, folderURL: NSURL) -> Bool {
		let dictionary = NSDictionary(dictionaryLiteral: (VersionFile.commitishKeyName, commitish), (VersionFile.buildProductSHA1KeyName, buildProductSHA1))
		do {
			let versionFileURL = folderURL.URLByAppendingPathComponent(".\(projectName).version")
			let jsonData = try NSJSONSerialization.dataWithJSONObject(dictionary, options: .PrettyPrinted)
			try jsonData.writeToURL(versionFileURL, options: .DataWritingAtomic)
		} catch {
			return false
		}
		return true
	}
	
	private static func readVersionFileForProjectNamed(projectName: String, folderURL: NSURL) -> VersionFile? {
		let versionFileURL = folderURL.URLByAppendingPathComponent(".\(projectName).version", isDirectory: false)
		guard let path = versionFileURL.path, versionFileData = NSData(contentsOfFile: path) else {
			return nil
		}
		
		guard let versionFileJSON = try? NSJSONSerialization.JSONObjectWithData(versionFileData, options: .AllowFragments) else {
			return nil
		}
		
		guard let versionFile: VersionFile = Argo.decode(versionFileJSON) else {
			return nil
		}
		
		return versionFile
	}
	
	private static func frameworkFileURL(folderURL: NSURL, projectName: String) -> NSURL? {
		let frameworkFolderURL = folderURL.URLByAppendingPathComponent("\(projectName).framework", isDirectory: true)
		let frameworkFileURL = frameworkFolderURL.URLByAppendingPathComponent("\(projectName)")
		return frameworkFileURL
	}
	
	private static func sha1ForFileAtURL(frameworkFileURL: NSURL) -> String? {
		guard let path = frameworkFileURL.path where NSFileManager.defaultManager().fileExistsAtPath(path) else {
			return nil
		}
		let frameworkData = NSData(contentsOfURL: frameworkFileURL)
		return frameworkData?.sha1()?.toHexString()
	}
}
