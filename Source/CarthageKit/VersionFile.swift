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
import ReactiveCocoa
import ReactiveTask
import Result

private struct CachedFramework {
	let name: String
	let md5: String
	
	static let nameKey = "name"
	static let md5Key = "md5"
	
	func toJSONObject() -> AnyObject {
		return [
			CachedFramework.nameKey: name,
			CachedFramework.md5Key: md5
		]
	}
}

extension CachedFramework: Decodable {
	static func decode(j: JSON) -> Decoded<CachedFramework> {
		return curry(self.init)
			<^> j <| CachedFramework.nameKey
			<*> j <| CachedFramework.md5Key
	}
}

private struct VersionFile {
	let commitish: String
	let xcodeVersion: String
	
	let macOS: [CachedFramework]?
	let iOS: [CachedFramework]?
	let watchOS: [CachedFramework]?
	let tvOS: [CachedFramework]?
	
	static let commitishKey = "commitish"
	static let xcodeVersionKey = "xcodeVersion"
	
	func cachesForPlatform(platform: Platform) -> [CachedFramework]? {
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
		return Set(Platform.supportedPlatforms.filter { self.cachesForPlatform($0) != nil })
	}
	
	func toJSONObject() -> AnyObject {
		var dict: [String: AnyObject] = [
			VersionFile.commitishKey : commitish,
			VersionFile.xcodeVersionKey : xcodeVersion
		]
		for platform in Platform.supportedPlatforms {
			if let caches = cachesForPlatform(platform) {
				dict[platform.rawValue] = caches.map { $0.toJSONObject() }
			}
		}
		return dict
	}
	
	init(commitish: String, xcodeVersion: String, macOS: [CachedFramework]?, iOS: [CachedFramework]?, watchOS: [CachedFramework]?, tvOS: [CachedFramework]?) {
		self.commitish = commitish
		self.xcodeVersion = xcodeVersion
		
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
	
	func check(platform: Platform, commitish: String, xcodeVersion: String, rootDirectoryURL: URL) -> SignalProducer<Bool, CarthageError> {
		guard commitish == self.commitish && xcodeVersion == self.xcodeVersion else {
			return .init(value: false)
		}
		
		let rootBinariesURL = rootDirectoryURL.appendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).URLByResolvingSymlinksInPath!
		guard let cachedFrameworks = cachesForPlatform(platform) else {
			return .init(value: false)
		}

		return SignalProducer<CachedFramework, CarthageError>(values: cachedFrameworks)
			.flatMap(.concat) { cachedFramework -> SignalProducer<Bool, CarthageError> in
				let platformURL = rootBinariesURL.appendingPathComponent(platform.rawValue, isDirectory: true).URLByResolvingSymlinksInPath!
				let frameworkURL = platformURL.appendingPathComponent("\(cachedFramework.name).framework", isDirectory: true)
				let frameworkBinaryURL = frameworkURL.appendingPathComponent("\(cachedFramework.name)", isDirectory: false)
				return md5ForFileAtURL(frameworkBinaryURL)
					.map { md5String in
						return cachedFramework.md5 == md5String
					}
			}
			.reduce(true) { (current: Bool, result: Bool) in
				return current && result
			}
	}
	
	func write(to url: URL) -> Result<(), CarthageError> {
		do {
			let json = toJSONObject()
			let jsonData = try NSJSONSerialization.dataWithJSONObject(json, options: .PrettyPrinted)
			try jsonData.writeToURL(url, options: .DataWritingAtomic)
			return .success(())
		} catch let error as NSError {
			return .failure(.writeFailed(url, error))
		}
	}
}

extension VersionFile: Decodable {
	static func decode(j: JSON) -> Decoded<VersionFile> {
		return curry(self.init)
			<^> j <| VersionFile.commitishKey
			<*> j <| VersionFile.xcodeVersionKey
			<*> j <||? Platform.macOS.rawValue
			<*> j <||? Platform.iOS.rawValue
			<*> j <||? Platform.watchOS.rawValue
			<*> j <||? Platform.tvOS.rawValue
	}
}

/// Creates a version file for the current dependency in the
/// Carthage/Build directory which associates its commitish with
/// the SHA1s of the built frameworks for each platform in order
/// to allow those frameworks to be skipped in future builds.
///
/// Returns a signal that succeeds once the file has been created.
public func createVersionFileForDependency(dependency: Dependency<PinnedVersion>, forPlatforms platforms: Set<Platform>, buildProductURLs: [URL], rootDirectoryURL: URL) -> SignalProducer<(), CarthageError> {
	var platformCaches: [String: [CachedFramework]] = [:]

	let platformsToCache = platforms.isEmpty ? Set(Platform.supportedPlatforms) : platforms
	for platform in platformsToCache {
		platformCaches[platform.rawValue] = []
	}

	return SignalProducer<URL, CarthageError>(values: buildProductURLs)
		.flatMap(.merge) { url -> SignalProducer<(), CarthageError> in
			guard let platformName = url.URLByDeletingLastPathComponent?.lastPathComponent,
				let frameworkName = url.URLByDeletingPathExtension?.lastPathComponent else {
					return .init(error: .versionFileError(description: "unable to construct version file path"))
			}
			let frameworkURL = url.appendingPathComponent(frameworkName, isDirectory: false)
			return md5ForFileAtURL(frameworkURL)
				.attemptMap { md5 -> Result<(), CarthageError> in
					let cachedFramework = CachedFramework(name: frameworkName, md5: md5)
					if var frameworks = platformCaches[platformName] {
						frameworks.append(cachedFramework)
						platformCaches[platformName] = frameworks
						return .success(())
					}
					else {
						return .failure(.versionFileError(description: "unexpected platform found in path"))
					}
				}
				.collect()
				.flatMap(.concat) { _ -> SignalProducer<String, CarthageError> in
					return currentXcodeVersion()
				}
				.attemptMap { xcodeVersion -> Result<(), CarthageError> in
					let rootBinariesURL = rootDirectoryURL.appendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).URLByResolvingSymlinksInPath!
					let versionFileURL = rootBinariesURL.appendingPathComponent(".\(dependency.project.name).version")

					let versionFile = VersionFile(
						commitish: dependency.version.commitish,
						xcodeVersion: xcodeVersion,
						macOS: platformCaches[Platform.macOS.rawValue],
						iOS: platformCaches[Platform.iOS.rawValue],
						watchOS: platformCaches[Platform.watchOS.rawValue],
						tvOS: platformCaches[Platform.tvOS.rawValue])

					return versionFile.write(to: versionFileURL)
				}
		}
}

/// Determines whether a dependency can be skipped because it is
/// already cached.
///
/// If a set of platforms is not provided and a version file exists,
/// the platforms in the version file are used instead.
///
/// Returns true if the the dependency can be skipped.
public func versionFileMatchesDependency(dependency: Dependency<PinnedVersion>, forPlatforms platforms: Set<Platform>, rootDirectoryURL: URL) -> SignalProducer<Bool, CarthageError> {
	let rootBinariesURL = rootDirectoryURL.appendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).URLByResolvingSymlinksInPath!
	let versionFileURL = rootBinariesURL.appendingPathComponent(".\(dependency.project.name).version")
	guard let versionFile = VersionFile(url: versionFileURL) else {
		return .init(value: false)
	}
	let commitish = dependency.version.commitish
	
	let cachedPlatforms = versionFile.cachedPlatforms()
	let platformsToCheck = platforms.isEmpty ? cachedPlatforms : platforms

	return currentXcodeVersion()
		.flatMap(.concat) { xcodeVersion in
			return SignalProducer<Platform, CarthageError>(values: platformsToCheck)
				.flatMap(.merge) { platform in
					return versionFile.check(platform, commitish: commitish, xcodeVersion: xcodeVersion, rootDirectoryURL: rootDirectoryURL)
				}
				.reduce(true) { current, result in
					return current && result
				}
		}
}

private func currentXcodeVersion() -> SignalProducer<String, CarthageError> {
	let task = Task("/usr/bin/xcrun", arguments: ["xcodebuild", "-version"])
	return task.launch()
		.mapError(CarthageError.taskError)
		.ignoreTaskData()
		.attemptMap { data in
			guard let versionString = String(data: data, encoding: .utf8) else {
				return .failure(.versionFileError(description: "Could not get xcode version"))
			}

			return .success(versionString.trimmingCharacters(in: .whitespacesAndNewlines))
	}
}

private func md5ForFileAtURL(frameworkFileURL: URL) -> SignalProducer<String, CarthageError> {
	guard let path = frameworkFileURL.path where NSFileManager.defaultManager().fileExistsAtPath(path) else {
		return .init(error: .versionFileError(description: "File does not exist for md5 generation \(frameworkFileURL)"))
	}
	let task = Task("/usr/bin/env", arguments: ["md5", "-q", frameworkFileURL.path!])
	return task.launch()
		.mapError(CarthageError.taskError)
		.ignoreTaskData()
		.attemptMap { data in
			guard let md5Str = String(data: data, encoding: .utf8) else {
				return .failure(.versionFileError(description: "Could not generate md5 for file \(frameworkFileURL)"))
			}
			return .success(md5Str.trimmingCharacters(in: .whitespacesAndNewlines))
		}
}
