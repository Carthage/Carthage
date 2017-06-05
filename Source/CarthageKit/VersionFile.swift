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
import XCDBLD

struct CachedFramework {
	let name: String
	let hash: String
	
	static let nameKey = "name"
	static let hashKey = "hash"
	
	func toJSONObject() -> Any {
		return [
			CachedFramework.nameKey: name,
			CachedFramework.hashKey: hash
		]
	}
}

extension CachedFramework: Decodable {
	static func decode(_ j: JSON) -> Decoded<CachedFramework> {
		return curry(self.init)
			<^> j <| CachedFramework.nameKey
			<*> j <| CachedFramework.hashKey
	}
}

struct VersionFile {
	let commitish: String

	let macOS: [CachedFramework]?
	let iOS: [CachedFramework]?
	let watchOS: [CachedFramework]?
	let tvOS: [CachedFramework]?
	
	static let commitishKey = "commitish"

	/// The extension representing a serialized VersionFile.
	static let pathExtension = "version"

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
		]
		for platform in Platform.supportedPlatforms {
			if let caches = self[platform] {
				dict[platform.rawValue] = caches.map { $0.toJSONObject() }
			}
		}
		return dict
	}

	init(commitish: String, macOS: [CachedFramework]?, iOS: [CachedFramework]?, watchOS: [CachedFramework]?, tvOS: [CachedFramework]?) {
		self.commitish = commitish
		
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

	func frameworkURL(for cachedFramework: CachedFramework, platform: Platform, binariesDirectoryURL: URL) -> URL {
		return binariesDirectoryURL
			.appendingPathComponent(platform.rawValue, isDirectory: true)
			.resolvingSymlinksInPath()
			.appendingPathComponent("\(cachedFramework.name).framework", isDirectory: true)
	}

	func frameworkBinaryURL(for cachedFramework: CachedFramework, platform: Platform, binariesDirectoryURL: URL) -> URL {
		return frameworkURL(for: cachedFramework, platform: platform, binariesDirectoryURL: binariesDirectoryURL)
			.appendingPathComponent("\(cachedFramework.name)", isDirectory: false)
	}

	/// Sends the hashes of the provided cached framework's binaries in the
	/// order that they were provided in.
	func hashes(for cachedFrameworks: [CachedFramework], platform: Platform, binariesDirectoryURL: URL) -> SignalProducer<String?, CarthageError> {
		return SignalProducer(cachedFrameworks)
			.flatMap(.concat) { cachedFramework -> SignalProducer<String?, CarthageError> in
				let frameworkBinaryURL = self.frameworkBinaryURL(for: cachedFramework, platform: platform, binariesDirectoryURL: binariesDirectoryURL)

				return hashForFileAtURL(frameworkBinaryURL)
					.map { hash -> String? in
						return hash
					}
					.flatMapError { _ in
						return SignalProducer(value: nil)
					}
			}
	}

	/// Sends values indicating whether the provided cached frameworks match the
	/// given local Swift version, in the order of the provided cached
	/// frameworks.
	///
	/// Non-Swift frameworks are considered as matching the local Swift version,
	/// as they will be compatible with it by definition.
	func swiftVersionMatches(for cachedFrameworks: [CachedFramework], platform: Platform, binariesDirectoryURL: URL, localSwiftVersion: String) -> SignalProducer<Bool, CarthageError> {
		return SignalProducer(cachedFrameworks)
			.flatMap(.concat) { cachedFramework -> SignalProducer<Bool, CarthageError> in
				let frameworkURL = self.frameworkURL(for: cachedFramework, platform: platform, binariesDirectoryURL: binariesDirectoryURL)

				return isSwiftFramework(frameworkURL)
					.flatMap(.concat) { isSwift -> SignalProducer<Bool, SwiftVersionError> in
						if !isSwift {
							return SignalProducer(value: true)
						}

						return frameworkSwiftVersion(frameworkURL).map { swiftVersion -> Bool in
							return swiftVersion == localSwiftVersion
						}
					}
					.flatMapError { _ in SignalProducer<Bool, CarthageError>(value: false) }
			}
	}

	func satisfies(platform: Platform, commitish: String, binariesDirectoryURL: URL, localSwiftVersion: String) -> SignalProducer<Bool, CarthageError> {
		guard let cachedFrameworks = self[platform] else {
			return SignalProducer(value: false)
		}

		let hashes = self.hashes(for: cachedFrameworks, platform: platform, binariesDirectoryURL: binariesDirectoryURL)
			.collect()

		let swiftVersionMatches = self.swiftVersionMatches(for: cachedFrameworks, platform: platform, binariesDirectoryURL: binariesDirectoryURL, localSwiftVersion: localSwiftVersion)
			.collect()

		return SignalProducer.zip(hashes, swiftVersionMatches)
			.flatMap(.concat) { hashes, swiftVersionMatches -> SignalProducer<Bool, CarthageError> in
				return self.satisfies(platform: platform, commitish: commitish, hashes: hashes, swiftVersionMatches: swiftVersionMatches)
			}
	}

	func satisfies(platform: Platform, commitish: String, hashes: [String?], swiftVersionMatches: [Bool]) -> SignalProducer<Bool, CarthageError> {
		guard let cachedFrameworks = self[platform], commitish == self.commitish else {
			return SignalProducer(value: false)
		}

		return SignalProducer
			.zip(
				SignalProducer(hashes),
				SignalProducer(cachedFrameworks),
				SignalProducer(swiftVersionMatches)
			)
			.map { (hash, cachedFramework, swiftVersionMatches) -> Bool in
				guard let hash = hash else {
					return false
				}
				return hash == cachedFramework.hash && swiftVersionMatches
			}
			.reduce(true) { (result, current) -> Bool in
				return result && current
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
			<*> j <||? Platform.macOS.rawValue
			<*> j <||? Platform.iOS.rawValue
			<*> j <||? Platform.watchOS.rawValue
			<*> j <||? Platform.tvOS.rawValue
	}
}

/// Creates a version file for the current dependency in the
/// Carthage/Build directory which associates its commitish with
/// the hashes (e.g. SHA256) of the built frameworks for each platform
/// in order to allow those frameworks to be skipped in future builds.
///
/// Returns a signal that succeeds once the file has been created.
public func createVersionFile(for dependency: Dependency, version: PinnedVersion, platforms: Set<Platform>, buildProducts: [URL], rootDirectoryURL: URL) -> SignalProducer<(), CarthageError> {
	return createVersionFileForCommitish(version.commitish, dependencyName: dependency.name, platforms: platforms, buildProducts: buildProducts, rootDirectoryURL: rootDirectoryURL)
}

/// Creates a version file for the dependency in the given root directory with:
/// - The given commitish
/// - The provided project name
/// - The location of the built frameworks products for all platforms
///
/// Returns a signal that succeeds once the file has been created.
public func createVersionFileForCommitish(_ commitish: String, dependencyName: String, platforms: Set<Platform> = Set(Platform.supportedPlatforms), buildProducts: [URL], rootDirectoryURL: URL) -> SignalProducer<(), CarthageError> {
	var platformCaches: [String: [CachedFramework]] = [:]

	let platformsToCache = platforms.isEmpty ? Set(Platform.supportedPlatforms) : platforms
	for platform in platformsToCache {
		platformCaches[platform.rawValue] = []
	}

	let writeVersionFile = SignalProducer<(), CarthageError>.attempt {
		let rootBinariesURL = rootDirectoryURL.appendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).resolvingSymlinksInPath()
		let versionFileURL = rootBinariesURL.appendingPathComponent(".\(dependencyName).\(VersionFile.pathExtension)")

		let versionFile = VersionFile(
			commitish: commitish,
			macOS: platformCaches[Platform.macOS.rawValue],
			iOS: platformCaches[Platform.iOS.rawValue],
			watchOS: platformCaches[Platform.watchOS.rawValue],
			tvOS: platformCaches[Platform.tvOS.rawValue])

		return versionFile.write(to: versionFileURL)
	}

	if !buildProducts.isEmpty {
		return SignalProducer<URL, CarthageError>(buildProducts)
			.flatMap(.merge) { url -> SignalProducer<String, CarthageError> in
				let platformName = url.deletingLastPathComponent().lastPathComponent
				let frameworkName = url.deletingPathExtension().lastPathComponent
				let frameworkURL = url.appendingPathComponent(frameworkName, isDirectory: false)
				return hashForFileAtURL(frameworkURL)
					.on(value: { hash in
						let cachedFramework = CachedFramework(name: frameworkName, hash: hash)
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
/// Returns an optional bool which is nil if no version file exists,
/// otherwise true if the version file matches and the build can be
/// skipped or false if there is a mismatch of some kind.
public func versionFileMatches(_ dependency: Dependency, version: PinnedVersion, platforms: Set<Platform>, rootDirectoryURL: URL, toolchain: String?) -> SignalProducer<Bool?, CarthageError> {
	let rootBinariesURL = rootDirectoryURL.appendingPathComponent(CarthageBinariesFolderPath, isDirectory: true).resolvingSymlinksInPath()
	let versionFileURL = rootBinariesURL.appendingPathComponent(".\(dependency.name).\(VersionFile.pathExtension)")
	guard let versionFile = VersionFile(url: versionFileURL) else {
		return SignalProducer(value: nil)
	}
	let commitish = version.commitish

	let platformsToCheck = platforms.isEmpty ? Set<Platform>(Platform.supportedPlatforms) : platforms

	return swiftVersion(usingToolchain: toolchain)
		.mapError { error in CarthageError.internalError(description: error.description) }
		.flatMap(.concat) { localSwiftVersion in
			return SignalProducer<Platform, CarthageError>(platformsToCheck)
				.flatMap(.merge) { platform in
					return versionFile.satisfies(platform: platform, commitish: commitish, binariesDirectoryURL: rootBinariesURL, localSwiftVersion: localSwiftVersion)
				}
				.reduce(true) { current, result in
					guard let current = current else {
						return false
					}
					return current && result
				}
		}
}

private func hashForFileAtURL(_ frameworkFileURL: URL) -> SignalProducer<String, CarthageError> {
	guard FileManager.default.fileExists(atPath: frameworkFileURL.path) else {
		return SignalProducer(error: .readFailed(frameworkFileURL, nil))
	}
	let task = Task("/usr/bin/shasum", arguments: ["-a", "256", frameworkFileURL.path])
	return task.launch()
		.mapError(CarthageError.taskError)
		.ignoreTaskData()
		.attemptMap { data in
			guard let taskOutput = String(data: data, encoding: .utf8) else {
				return .failure(.readFailed(frameworkFileURL, nil))
			}
			let hashStr = taskOutput.components(separatedBy: CharacterSet.whitespaces)[0]
			return .success(hashStr.trimmingCharacters(in: .whitespacesAndNewlines))
		}
}
