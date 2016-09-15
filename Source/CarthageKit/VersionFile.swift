//
//  VersionFile.swift
//  Carthage
//
//  Created by Jason Boyle on 8/11/16.
//  Copyright © 2016 Carthage. All rights reserved.
//

import Foundation

private let commitishKeyName = "commitish"
private let cachedFrameworksKeyName = "cachedFrameworks"
private let frameworkNameKeyName = "frameworkName"
private let frameworkSha1KeyName = "frameworkSha1"

private typealias VersionFile = [String: [String: AnyObject]]

public func createVersionFileForDependency(dependency: Dependency<PinnedVersion>, forPlatforms platforms: Set<Platform>, buildProductURLs: [NSURL], rootDirectoryURL: NSURL) -> Bool {
	var cachedPlatformFrameworks: [String: [[String: String]]] = [:]
	
	for url in buildProductURLs {
		guard let platformName = url.URLByDeletingLastPathComponent?.lastPathComponent else { return false }
		guard let frameworkName = url.URLByDeletingPathExtension?.lastPathComponent else { return false }
		
		let frameworkURL = url.appendingPathComponent(frameworkName, isDirectory: false)
		guard NSFileManager.defaultManager().fileExistsAtPath(frameworkURL.path!) else { return false }
		guard let sha1 = sha1ForFileAtURL(frameworkURL) else { return false }
		
		let frameworkInfo = [frameworkNameKeyName: frameworkName, frameworkSha1KeyName: sha1]
		
		var frameworks = cachedPlatformFrameworks[platformName] ?? []
		frameworks.append(frameworkInfo)
		cachedPlatformFrameworks[platformName] = frameworks
	}
	
	var versionInfo: VersionFile = [:]
	
	let platformSet = platforms.isEmpty ? Set(Platform.supportedPlatforms) : platforms
	for platform in platformSet {
		let cachedFrameworks: [[String: String]] = cachedPlatformFrameworks[platform.rawValue] ?? []
		versionInfo[platform.rawValue] = [commitishKeyName: dependency.version.commitish, cachedFrameworksKeyName: cachedFrameworks]
	}
	
	let rootBinariesURL = rootDirectoryURL.appendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).URLByResolvingSymlinksInPath!
	let versionFileURL = rootBinariesURL.appendingPathComponent(".\(dependency.project.name).version")
	
	if let oldVersionFile: VersionFile = readVersionFileAtURL(versionFileURL) {
		for platformName in oldVersionFile.keys {
			if versionInfo[platformName] == nil {
				versionInfo[platformName] = oldVersionFile[platformName]
			}
		}
	}

	do {
		let jsonData = try NSJSONSerialization.dataWithJSONObject(versionInfo, options: .PrettyPrinted)
		try jsonData.writeToURL(versionFileURL, options: .DataWritingAtomic)
	}
	catch { return false }
	
	return true
}

public func versionFileMatchesDependency(dependency: Dependency<PinnedVersion>, forPlatforms platforms: Set<Platform>, rootDirectoryURL: NSURL) -> Bool {
	let rootBinariesURL = rootDirectoryURL.appendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).URLByResolvingSymlinksInPath!
	let versionFileURL = rootBinariesURL.appendingPathComponent(".\(dependency.project.name).version")
	guard let versionInfo = readVersionFileAtURL(versionFileURL) else { return false }
	
	let platformNames: [String] = !platforms.isEmpty ? platforms.map { $0.rawValue } : Array(versionInfo.keys)
	guard platformNames.count > 0 else { return false }
	
	for platformName in platformNames {
		guard let platformInfo: [String: AnyObject] = versionInfo[platformName] else { return false }
		guard let commitish = platformInfo[commitishKeyName] as? String where commitish == dependency.version.commitish	else { return false }
		guard let cachedFrameworks = platformInfo[cachedFrameworksKeyName] as? [[String: String]] else { return false }
		
		for frameworkInfo in cachedFrameworks {
			guard let frameworkName = frameworkInfo[frameworkNameKeyName] else { return false }
			guard let frameworkSha1 = frameworkInfo[frameworkSha1KeyName] else { return false }
			
			let platformURL = rootBinariesURL.appendingPathComponent(platformName, isDirectory: true).URLByResolvingSymlinksInPath!
			let frameworkURL = platformURL.appendingPathComponent("\(frameworkName).framework", isDirectory: true)
			let frameworkBinaryURL = frameworkURL.appendingPathComponent("\(frameworkName)", isDirectory: false)
			guard let sha1 = sha1ForFileAtURL(frameworkBinaryURL) where sha1 == frameworkSha1 else { return false }
		}
	}
	
	return true
}

private func sha1ForFileAtURL(frameworkFileURL: NSURL) -> String? {
	guard let path = frameworkFileURL.path where NSFileManager.defaultManager().fileExistsAtPath(path) else { return nil }
	let frameworkData = try? NSData(contentsOfFile: path, options: .DataReadingMappedAlways)
	return frameworkData?.sha1()?.toHexString() // shasum
}

private func readVersionFileAtURL(url: NSURL) -> VersionFile? {
	guard NSFileManager.defaultManager().fileExistsAtPath(url.path!) else { return nil }
	guard let jsonData = NSData(contentsOfFile: url.path!) else { return nil }
	guard let json = try? NSJSONSerialization.JSONObjectWithData(jsonData, options: .AllowFragments) else { return nil }
	return json as? VersionFile
}
