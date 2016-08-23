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


public struct CachedFramework {
	public let frameworkName: String
	public let frameworkSHA1: String
	
	public static let frameworkNameKeyName = "frameworkName"
	public static let frameworkSHA1KeyName = "frameworkSHA1"
	
	public init(frameworkName: String, frameworkSHA1: String) {
		self.frameworkName = frameworkName
		self.frameworkSHA1 = frameworkSHA1
	}
}

extension CachedFramework: Decodable {
	public static func decode(j: JSON) -> Decoded<CachedFramework> {
		return curry(self.init)
			<^> j <| CachedFramework.frameworkNameKeyName
			<*> j <| CachedFramework.frameworkSHA1KeyName
	}
}


public struct CachedFrameworks {
	public let commitish: String
	public let cachedFrameworks: [CachedFramework]
	
	public static let commitishKeyName = "commitish"
	public static let cachedFrameworksKeyName = "cachedFrameworks"
	
	public init(commitish: String, cachedFrameworks: [CachedFramework]) {
		self.commitish = commitish
		self.cachedFrameworks = cachedFrameworks
	}
}

extension CachedFrameworks: Decodable {
	public static func decode(j: JSON) -> Decoded<CachedFrameworks> {
		return curry(self.init)
			<^> j <| CachedFrameworks.commitishKeyName
			<*> j <|| CachedFrameworks.cachedFrameworksKeyName
	}
}


private func sha1ForFileAtURL(frameworkFileURL: NSURL) -> String? {
	guard let path = frameworkFileURL.path where NSFileManager.defaultManager().fileExistsAtPath(path) else {
		return nil
	}
	let frameworkData = NSData(contentsOfURL: frameworkFileURL)
	return frameworkData?.sha1()?.toHexString()
}

public func createVersionFilesForDependency(dependency: Dependency<PinnedVersion>, buildProductURLs: [NSURL]) -> Bool {
	var dataByPlatform: [NSURL: [[String: String]]] = [:]
	for url in buildProductURLs {
		guard let platformURL = url.URLByDeletingLastPathComponent else { return false }
		guard let frameworkName = url.URLByDeletingPathExtension?.lastPathComponent else { return false }
		let frameworkURL = url.URLByAppendingPathComponent(frameworkName, isDirectory: false)
		guard let sha1 = sha1ForFileAtURL(frameworkURL) else { return false }
		
		var platformData: [[String: String]] = dataByPlatform[platformURL] ?? []
		platformData.append([CachedFramework.frameworkNameKeyName: frameworkName, CachedFramework.frameworkSHA1KeyName: sha1])
		dataByPlatform[platformURL] = platformData
	}
	do {
		for (platformURL, platformData) in dataByPlatform {
			let versionFileURL = platformURL.URLByAppendingPathComponent(".\(dependency.project.name).version")
			let versionData = [CachedFrameworks.commitishKeyName: dependency.version.commitish, CachedFrameworks.cachedFrameworksKeyName: platformData]
			
			let jsonData = try NSJSONSerialization.dataWithJSONObject(versionData, options: .PrettyPrinted)
			try jsonData.writeToURL(versionFileURL, options: .DataWritingAtomic)
		}
	}
	catch {
		return false
	}
	return true
}

public func createVersionFilesForDependencyWithNoBuildProducts(dependency: Dependency<PinnedVersion>, directoryURL: NSURL, platforms: Set<Platform>) -> Bool {
	do {
		for platform in platforms {
			let platformURL = directoryURL.URLByAppendingPathComponent(platform.relativePath, isDirectory: true).URLByResolvingSymlinksInPath!
			
			let versionFileURL = platformURL.URLByAppendingPathComponent(".\(dependency.project.name).version")
			let versionData = [CachedFrameworks.commitishKeyName: dependency.version.commitish, CachedFrameworks.cachedFrameworksKeyName: []]
			
			let jsonData = try NSJSONSerialization.dataWithJSONObject(versionData, options: .PrettyPrinted)
			try jsonData.writeToURL(versionFileURL, options: .DataWritingAtomic)
		}
	}
	catch {
		return false
	}
	return true
}

public func versionFilesMatchDependency(dependency: Dependency<PinnedVersion>, forPlatforms platforms: Set<Platform>, directoryURL: NSURL) -> Bool {
	let dependencyURL = directoryURL.URLByAppendingPathComponent(dependency.project.relativePath, isDirectory: true).URLByResolvingSymlinksInPath!
	for platform in platforms {
		let platformURL = dependencyURL.URLByAppendingPathComponent(platform.relativePath, isDirectory: true).URLByResolvingSymlinksInPath!
		let versionFileURL = platformURL.URLByAppendingPathComponent(".\(dependency.project.name).version")
		if !NSFileManager.defaultManager().fileExistsAtPath(versionFileURL.path!) {
			return false
		}
		guard let jsonData = NSData(contentsOfFile: versionFileURL.path!) else {
			return false
		}
		guard let json = try? NSJSONSerialization.JSONObjectWithData(jsonData, options: .AllowFragments) else {
			return false
		}
		guard let cachedFrameworks: CachedFrameworks = Argo.decode(json) else {
			return false
		}
		guard cachedFrameworks.commitish == dependency.version.commitish else {
			return false
		}
		for cachedFramework in cachedFrameworks.cachedFrameworks {
			let frameworkURL = platformURL.URLByAppendingPathComponent("\(cachedFramework.frameworkName).framework", isDirectory: true)
			let frameworkBinaryURL = frameworkURL.URLByAppendingPathComponent("\(cachedFramework.frameworkName)", isDirectory: false)
			guard let frameworkSHA1 = sha1ForFileAtURL(frameworkBinaryURL) where frameworkSHA1 == cachedFramework.frameworkSHA1 else {
				return false
			}
		}
	}
	return true
}
