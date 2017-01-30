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
	
	func cachesForPlatform(_ platform: Platform) -> [CachedFramework]? {
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
	
	func toJSONObject() -> Any {
		var dict: [String: Any] = [
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
		guard FileManager.default.fileExists(atPath: url.path),
			let jsonData = try? Data(contentsOf: url),
			let json = try? JSONSerialization.jsonObject(with: jsonData, options: .allowFragments),
			let versionFile: VersionFile = Argo.decode(json) else {
			return nil
		}
		self = versionFile
	}
	
	func check(_ platform: Platform, commitish: String, xcodeVersion: String, rootDirectoryURL: URL) -> SignalProducer<Bool, CarthageError> {
		guard commitish == self.commitish && xcodeVersion == self.xcodeVersion else {
			return .init(value: false)
		}
		
		let rootBinariesURL = rootDirectoryURL.appendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).resolvingSymlinksInPath()
		guard let cachedFrameworks = cachesForPlatform(platform) else {
			return .init(value: false)
		}

		return SignalProducer<CachedFramework, CarthageError>(cachedFrameworks)
			.flatMap(.concat) { cachedFramework -> SignalProducer<Bool, CarthageError> in
				let platformURL = rootBinariesURL.appendingPathComponent(platform.rawValue, isDirectory: true).resolvingSymlinksInPath()
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
/// the SHA1s of the built frameworks for each platform in order
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
		.flatMap(.merge) { url -> SignalProducer<(), CarthageError> in
			let platformName = url.deletingLastPathComponent().lastPathComponent
			let frameworkName = url.deletingPathExtension().lastPathComponent
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
				.flatMap(.concat) { _ -> SignalProducer<(), CarthageError> in
					return writeVersionFile
				}
		}
	} else {
		// Write out an empty version file for dependencies with no built frameworks, so cache builds can differentiate between
		// no cache and a dependency that has no frameworks
		return writeVersionFile
	}
}

/// Determines whether a dependency can be skipped because it is
/// already cached.
///
/// If a set of platforms is not provided and a version file exists,
/// the platforms in the version file are used instead.
///
/// Returns true if the the dependency can be skipped.
public func versionFileMatchesDependency(_ dependency: Dependency<PinnedVersion>, forPlatforms platforms: Set<Platform>, rootDirectoryURL: URL) -> SignalProducer<Bool, CarthageError> {
	let rootBinariesURL = rootDirectoryURL.appendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).resolvingSymlinksInPath()
	let versionFileURL = rootBinariesURL.appendingPathComponent(".\(dependency.project.name).version")
	guard let versionFile = VersionFile(url: versionFileURL) else {
		return .init(value: false)
	}
	let commitish = dependency.version.commitish
	
	let cachedPlatforms = versionFile.cachedPlatforms()
	let platformsToCheck = platforms.isEmpty ? cachedPlatforms : platforms

	return currentXcodeVersion()
		.flatMap(.concat) { xcodeVersion in
			return SignalProducer<Platform, CarthageError>(platformsToCheck)
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

private func md5ForFileAtURL(_ frameworkFileURL: URL) -> SignalProducer<String, CarthageError> {
	guard FileManager.default.fileExists(atPath: frameworkFileURL.path) else {
		return .init(error: .versionFileError(description: "File does not exist for md5 generation \(frameworkFileURL)"))
	}
	let task = Task("/usr/bin/env", arguments: ["md5", "-q", frameworkFileURL.path])
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
