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

private struct CachedFramework {
	let name: String
	let sha1: String
	
	static let nameKey = "name"
	static let sha1Key = "sha1"
	
	func toJSONObject() -> AnyObject {
		return [
			CachedFramework.nameKey: name,
			CachedFramework.sha1Key: sha1
		]
	}
}

extension CachedFramework: Decodable {
	static func decode(j: JSON) -> Decoded<CachedFramework> {
		return curry(self.init)
			<^> j <| CachedFramework.nameKey
			<*> j <| CachedFramework.sha1Key
	}
}

private struct CachedPlatform {
	let commitish: String
	let cachedFrameworks: [CachedFramework]
	
	static let commitishKey = "commitish"
	static let cachedFrameworksKey = "cachedFrameworks"
	
	func toJSONObject() -> AnyObject {
		let array = cachedFrameworks.map { $0.toJSONObject() }
		return [
			CachedPlatform.commitishKey: commitish,
			CachedPlatform.cachedFrameworksKey: array
		]
	}
}

extension CachedPlatform: Decodable {
	static func decode(j: JSON) -> Decoded<CachedPlatform> {
		return curry(self.init)
			<^> j <| CachedPlatform.commitishKey
			<*> j <|| CachedPlatform.cachedFrameworksKey
	}
}

private struct VersionFile {
	let macOS: CachedPlatform?
	let iOS: CachedPlatform?
	let watchOS: CachedPlatform?
	let tvOS: CachedPlatform?
	
	func cacheForPlatform(platform: Platform) -> CachedPlatform? {
		switch platform {
		case .macOS:
			return macOS
		case .iOS:
			return iOS
		case .watchOS:
			return watchOS
		case .tvOS:
			return tvOS
		}
	}
	
	func cachedPlatforms() -> Set<Platform> {
		return Set(Platform.supportedPlatforms.filter { self.cacheForPlatform($0) != nil })
	}
	
	func toJSONObject() -> AnyObject {
		return Platform.supportedPlatforms.reduce([String: AnyObject](), combine: { (dict, platform) in
			var dict = dict
			dict[platform.rawValue] = cacheForPlatform(platform)?.toJSONObject()
			return dict
		})
	}
	
	init(macOS: CachedPlatform?, iOS: CachedPlatform?, watchOS: CachedPlatform?, tvOS: CachedPlatform?) {
		self.macOS = macOS
		self.iOS = iOS
		self.watchOS = watchOS
		self.tvOS = tvOS
	}
	
	init?(url: URL) {
		guard NSFileManager.defaultManager().fileExistsAtPath(url.path!),
			let jsonData = NSData(contentsOfFile: url.path!),
			let json = try? NSJSONSerialization.JSONObjectWithData(jsonData, options: .AllowFragments),
			let versionFile: VersionFile = Argo.decode(json) else {
			return nil
		}
		self = versionFile
	}
	
	func checkPlatform(platform: Platform, commitish: String, rootDirectoryURL: URL) -> Bool {
		let rootBinariesURL = rootDirectoryURL.appendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).URLByResolvingSymlinksInPath!
		
		guard let cachedPlatform = cacheForPlatform(platform) where commitish == cachedPlatform.commitish else {
			return false
		}
		
		let cachedFrameworks: [CachedFramework] = cachedPlatform.cachedFrameworks
		for cachedFramework in cachedFrameworks {
			let platformURL = rootBinariesURL.appendingPathComponent(platform.rawValue, isDirectory: true).URLByResolvingSymlinksInPath!
			let frameworkURL = platformURL.appendingPathComponent("\(cachedFramework.name).framework", isDirectory: true)
			let frameworkBinaryURL = frameworkURL.appendingPathComponent("\(cachedFramework.name)", isDirectory: false)
			guard let sha1 = sha1ForFileAtURL(frameworkBinaryURL) where sha1 == cachedFramework.sha1 else {
				return false
			}
		}
		
		return true
	}
	
	func write(to url: URL) -> Bool {
		do {
			let json = toJSONObject()
			let jsonData = try NSJSONSerialization.dataWithJSONObject(json, options: .PrettyPrinted)
			try jsonData.writeToURL(url, options: .DataWritingAtomic)
		}
		catch {
			return false
		}
		return true
	}
}

extension VersionFile: Decodable {
	static func decode(j: JSON) -> Decoded<VersionFile> {
		return curry(self.init)
			<^> j <|? Platform.macOS.rawValue
			<*> j <|? Platform.iOS.rawValue
			<*> j <|? Platform.watchOS.rawValue
			<*> j <|? Platform.tvOS.rawValue
	}
}

/// Creates a version file for the current dependency in the
/// Carthage/Build directory which associates its commitish with
/// the SHA1s of the built frameworks for each platform in order
/// to allow those frameworks to be skipped in future builds.
///
/// Returns true if the version file was successfully created.
public func createVersionFileForDependency(dependency: Dependency<PinnedVersion>, forPlatforms platforms: Set<Platform>, buildProductURLs: [URL], rootDirectoryURL: URL) -> Bool {
	var frameworksByPlatform: [String: [CachedFramework]] = [:]
	
	for url in buildProductURLs {
		guard let platformName = url.URLByDeletingLastPathComponent?.lastPathComponent,
			let frameworkName = url.URLByDeletingPathExtension?.lastPathComponent else {
			return false
		}
		let frameworkURL = url.appendingPathComponent(frameworkName, isDirectory: false)
		guard let sha1 = sha1ForFileAtURL(frameworkURL) else {
			return false
		}
		let cachedFramework = CachedFramework(name: frameworkName, sha1: sha1)
		
		var frameworks = frameworksByPlatform[platformName] ?? []
		frameworks.append(cachedFramework)
		frameworksByPlatform[platformName] = frameworks
	}
	
	var cachedPlatforms: [String: CachedPlatform] = frameworksByPlatform.reduce([:]) { (cachedPlatforms, entry: (platformName: String, cachedFrameworks: [CachedFramework])) in
		var cachedPlatforms = cachedPlatforms
		cachedPlatforms[entry.platformName] = CachedPlatform(commitish: dependency.version.commitish, cachedFrameworks: entry.cachedFrameworks)
		return cachedPlatforms
	}
	
	let rootBinariesURL = rootDirectoryURL.appendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).URLByResolvingSymlinksInPath!
	let versionFileURL = rootBinariesURL.appendingPathComponent(".\(dependency.project.name).version")
	
	if let oldVersionFile = VersionFile(url: versionFileURL) {
		for platform in Platform.supportedPlatforms {
			if let oldCachedPlatform = oldVersionFile.cacheForPlatform(platform) where cachedPlatforms[platform.rawValue] == nil {
				cachedPlatforms[platform.rawValue] = oldCachedPlatform
			}
		}
	}
	
	let versionFile = VersionFile(
		macOS: cachedPlatforms[Platform.macOS.rawValue],
		iOS: cachedPlatforms[Platform.iOS.rawValue],
		watchOS: cachedPlatforms[Platform.watchOS.rawValue],
		tvOS: cachedPlatforms[Platform.tvOS.rawValue])
	
	return versionFile.write(to: versionFileURL)
}

/// Determines whether a dependency can be skipped.  If a version file
/// for the dependency project exists, and its commitish matches, and
/// the recorded SHA1s are the same as the computed SHA1s of each
/// framework in the Carthage/Build directory for the given platforms,
/// the dependency can be skipped.
///
/// If a set of platforms is not provided and a version file exists,
/// the platforms listed in the version file are used instead.
///
/// Returns true if the the dependency can be skipped.
public func versionFileMatchesDependency(dependency: Dependency<PinnedVersion>, forPlatforms platforms: Set<Platform>, rootDirectoryURL: URL) -> Bool {
	let rootBinariesURL = rootDirectoryURL.appendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).URLByResolvingSymlinksInPath!
	let versionFileURL = rootBinariesURL.appendingPathComponent(".\(dependency.project.name).version")
	guard let versionFile = VersionFile(url: versionFileURL) else {
		return false
	}
	let commitish = dependency.version.commitish
	
	let cachedPlatforms = versionFile.cachedPlatforms()
	let platformsToCheck = platforms.isEmpty ? cachedPlatforms : platforms
	for platform in platformsToCheck {
		if !versionFile.checkPlatform(platform, commitish: commitish, rootDirectoryURL: rootDirectoryURL) {
			return false
		}
	}
	
	return true
}

private func sha1ForFileAtURL(frameworkFileURL: URL) -> String? {
	guard let path = frameworkFileURL.path where NSFileManager.defaultManager().fileExistsAtPath(path) else {
		return nil
	}
	let frameworkData = try? NSData(contentsOfFile: path, options: .DataReadingMappedAlways)
	return frameworkData?.sha1()?.toHexString() // shasum
}
