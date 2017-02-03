//
//  VersionFile.swift
//  Carthage
//
//  Created by Jason Boyle on 8/11/16.
//  Copyright © 2016 Carthage. All rights reserved.
//

import Foundation
import Runes
import Argo
import Curry
import ReactiveSwift
import ReactiveTask
import Result

private struct CachedFramework {
	let name: String
	let md5: String
	
	static let nameKey = "name"
	static let md5Key = "md5"
	
	func toJSONObject() -> Any {
		return [
			CachedFramework.nameKey: name,
			CachedFramework.md5Key: md5
		]
	}
}

extension CachedFramework: Decodable {
	static func decode(_ j: JSON) -> Decoded<CachedFramework> {
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

	subscript(_ platform: Platform) -> [CachedFramework]? {
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
	
	func toJSONObject() -> Any {
		var dict: [String: Any] = [
			VersionFile.commitishKey : commitish,
			VersionFile.xcodeVersionKey : xcodeVersion
		]
		for platform in Platform.supportedPlatforms {
			if let caches = self[platform] {
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
		guard FileManager.default.fileExists(atPath: url.path),
			let jsonData = try? Data(contentsOf: url),
			let json = try? JSONSerialization.jsonObject(with: jsonData, options: .allowFragments),
			let versionFile: VersionFile = Argo.decode(json) else {
			return nil
		}
		self = versionFile
	}

	func satisfies(platform: Platform, commitish: String, xcodeVersion: String, binariesDirectoryURL: URL) -> SignalProducer<Bool, CarthageError> {
		guard let cachedFrameworks = self[platform] else {
			return .init(value: false)
		}

		return SignalProducer<CachedFramework, CarthageError>(cachedFrameworks)
			.flatMap(.concat) { cachedFramework -> SignalProducer<(String, String), CarthageError> in
				let frameworkName = cachedFramework.name
				let platformURL = binariesDirectoryURL.appendingPathComponent(platform.rawValue, isDirectory: true).resolvingSymlinksInPath()
				let frameworkURL = platformURL.appendingPathComponent("\(frameworkName).framework", isDirectory: true)
				let frameworkBinaryURL = frameworkURL.appendingPathComponent("\(frameworkName)", isDirectory: false)

				return md5ForFileAtURL(frameworkBinaryURL)
					.map { md5String in
						return (frameworkName, md5String)
					}
			}
			.collect()
			.map { frameworksAndMd5s -> [String: String] in
				var dict: [String: String] = [:]
				for (frameworkName, md5) in frameworksAndMd5s {
					dict[frameworkName] = md5
				}
				return dict
			}
			.flatMap(.concat) { md5Map in
				return self.satisfies(platform: platform, commitish: commitish, xcodeVersion: xcodeVersion, md5s: md5Map)
			}
	}

	func satisfies(platform: Platform, commitish: String, xcodeVersion: String, md5s: [String: String]) -> SignalProducer<Bool, CarthageError> {
		guard let cachedFrameworks = self[platform], commitish == self.commitish, xcodeVersion == self.xcodeVersion else {
			return .init(value: false)
		}

		return SignalProducer<CachedFramework, CarthageError>(cachedFrameworks)
			.map { cachedFramework in
				guard let currentMd5 = md5s[cachedFramework.name] else {
					return false
				}

				return cachedFramework.md5 == currentMd5
			}
			.reduce(true) { (current: Bool, result: Bool) in
				return current && result
			}
	}

	func write(to url: URL) -> Result<(), CarthageError> {
		do {
			let json = toJSONObject()
			let jsonData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
			try jsonData.write(to: url, options: .atomic)
			return .success(())
		} catch let error as NSError {
			return .failure(.writeFailed(url, error))
		}
	}
}

extension VersionFile: Decodable {
	static func decode(_ j: JSON) -> Decoded<VersionFile> {
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
/// the MD5s of the built frameworks for each platform in order
/// to allow those frameworks to be skipped in future builds.
///
/// Returns a signal that succeeds once the file has been created.
public func createVersionFileForDependency(_ dependency: Dependency<PinnedVersion>, forPlatforms platforms: Set<Platform>, buildProductURLs: [URL], rootDirectoryURL: URL) -> SignalProducer<(), CarthageError> {
	var platformCaches: [String: [CachedFramework]] = [:]

	let platformsToCache = platforms.isEmpty ? Set(Platform.supportedPlatforms) : platforms
	for platform in platformsToCache {
		platformCaches[platform.rawValue] = []
	}


	let writeVersionFile = currentXcodeVersion()
		.attemptMap { xcodeVersion -> Result<(), CarthageError> in
			let rootBinariesURL = rootDirectoryURL.appendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).resolvingSymlinksInPath()
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

	if !buildProductURLs.isEmpty {
		return SignalProducer<URL, CarthageError>(buildProductURLs)
		.flatMap(.merge) { url -> SignalProducer<String, CarthageError> in
			let platformName = url.deletingLastPathComponent().lastPathComponent
			let frameworkName = url.deletingPathExtension().lastPathComponent
			let frameworkURL = url.appendingPathComponent(frameworkName, isDirectory: false)
			return md5ForFileAtURL(frameworkURL)
				.on(value: { md5 in
					let cachedFramework = CachedFramework(name: frameworkName, md5: md5)
					if var frameworks = platformCaches[platformName] {
						frameworks.append(cachedFramework)
						platformCaches[platformName] = frameworks
					}
				})
		}
		.then(writeVersionFile)
	} else {
		// Write out an empty version file for dependencies with no built frameworks, so cache builds can differentiate between
		// no cache and a dependency that has no frameworks
		return writeVersionFile
	}
}

/// Determines whether a dependency can be skipped because it is
/// already cached.
///
/// If a set of platforms is not provided, all platforms are checked.
///
/// Returns true if the the dependency can be skipped.
public func versionFileMatchesDependency(_ dependency: Dependency<PinnedVersion>, forPlatforms platforms: Set<Platform>, rootDirectoryURL: URL) -> SignalProducer<Bool, CarthageError> {
	let rootBinariesURL = rootDirectoryURL.appendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).resolvingSymlinksInPath()
	let versionFileURL = rootBinariesURL.appendingPathComponent(".\(dependency.project.name).version")
	guard let versionFile = VersionFile(url: versionFileURL) else {
		return .init(value: false)
	}
	let commitish = dependency.version.commitish

	let platformsToCheck = platforms.isEmpty ? Set<Platform>(Platform.supportedPlatforms) : platforms

	return currentXcodeVersion()
		.flatMap(.concat) { xcodeVersion in
			return SignalProducer<Platform, CarthageError>(platformsToCheck)
				.flatMap(.merge) { platform in
					return versionFile.satisfies(platform: platform, commitish: commitish, xcodeVersion: xcodeVersion, binariesDirectoryURL: rootBinariesURL)
				}
				.reduce(true) { current, result in
					return current && result
				}
		}
}

private func md5ForFileAtURL(_ frameworkFileURL: URL) -> SignalProducer<String, CarthageError> {
	guard FileManager.default.fileExists(atPath: frameworkFileURL.path) else {
		return .init(error: .readFailed(frameworkFileURL, nil))
	}
	let task = Task("/usr/bin/env", arguments: ["md5", "-q", frameworkFileURL.path])
	return task.launch()
		.mapError(CarthageError.taskError)
		.ignoreTaskData()
		.attemptMap { data in
			guard let md5Str = String(data: data, encoding: .utf8) else {
				return .failure(.readFailed(frameworkFileURL, nil))
			}
			return .success(md5Str.trimmingCharacters(in: .whitespacesAndNewlines))
		}
}
