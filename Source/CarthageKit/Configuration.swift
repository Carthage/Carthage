//
//  Configuration.swift
//  carthage
//
//  Created by Lincoln Law on 2018/1/4.
//  Copyright © 2018年 Carthage. All rights reserved.
//

import Foundation
import XCDBLD
import PrettyColors

public final class Configuration {
	public static let shared = Configuration()
	/// The Xcode configuration to build.
	public var configuration: String = "Release"
	/// The platforms to build for.
	public var platforms: Set<Platform> = Set(Platform.supportedPlatforms)
	/// Rebuild even if cached builds exist.
	public var isEnableCacheBuilds: Bool = false
	public var isEnableNewResolver: Bool = false
	public var isEnableVerbose: Bool = false
	public var isUsingSSH: Bool = false
	public var isUsingSubmodules: Bool = false
	public var skippableDependencies: [SkippableDepency] = []
	public var overridableDependencies: [String : Dependency] = [:]
	public var totalDependencies: [String : Dependency] = [:]
	
//	public var 
	
	private init() { }
	
	public func readConfig() {
		guard let pwd = ProcessInfo.processInfo.environment["PWD"] else { return }
		let privateCartfilePath = "\(pwd)/\(Constants.Project.privateCartfilePath)"
		guard let content = try? String.init(contentsOfFile: privateCartfilePath) else { return }
		
		content.enumerateLines { (line, ioStop) in
			let trimLine = line.trim
			if trimLine.hasPrefix(Key.override) {
				self.readOverridableDependency(from: trimLine)
			} else if trimLine.hasPrefix(Key.skip) {
				self.readSkippableDependency(from: trimLine)
			} else if trimLine.hasPrefix(Key.platforms) {
				self.readPlatform(from: trimLine)
			} else if trimLine.hasPrefix(Key.configuration) {
				self.readConfiguration(from: trimLine)
			} else if trimLine.hasPrefix(Key.cacheBuilds) {
				self.isEnableCacheBuilds = Key.cacheBuilds.bool(from: trimLine)
			} else if trimLine.hasPrefix(Key.newResolver) {
				self.isEnableNewResolver = Key.newResolver.bool(from: trimLine)
			} else if trimLine.hasPrefix(Key.verbose) {
				self.isEnableVerbose = Key.verbose.bool(from: trimLine)
			} else if trimLine.hasPrefix(Key.useSubmodules) {
				self.isUsingSubmodules = Key.useSubmodules.bool(from: trimLine)
			}
		}
	}
	
	private func readPlatform(from line: String) {
		let trimLine = line.replacingOccurrences(of: Key.platforms.rawValue, with: "").trim
		if trimLine.isEmpty { return }
		let preferPlatforms = trimLine.components(separatedBy: ",").flatMap({ Platform.from($0) })
		platforms = Set(preferPlatforms)
	}
	
	private func readConfiguration(from line: String) {
		var trimLine = line.replacingOccurrences(of: Key.configuration.rawValue, with: "").trim
		if ["release", "debug"].contains(trimLine.lowercased()) {
			trimLine = trimLine.capitalized
		}
		configuration = trimLine
	}
	
	private func readSkippableDependency(from line: String) {
		let trimLine = line.replacingOccurrences(of: Key.skip.rawValue, with: "").trim
		let components = trimLine.components(separatedBy: ",")
		guard let name = components[c_safe: 0]?.trim else { return }
		let workspaceOrProject = components[c_safe: 1]?.trim
		let scheme = components[c_safe: 2]?.trim
		let dependency = SkippableDepency(name: name, scheme: scheme, workspaceOrProject: workspaceOrProject)
		skippableDependencies.append(dependency)
	}
	
	private func readOverridableDependency(from line: String) {
		let components = line.replacingOccurrences(of: Key.override.rawValue, with: "").trim.components(separatedBy: ",")
		guard let name = components[c_safe: 0]?.trim, let path = components[c_safe: 1]?.trim else { return }
		let denpendency = Dependency.git(GitURL(path))
		overridableDependencies[name] = denpendency
	}
	
	public func runOptions() -> String {

		let configurationString = "--configuration \(configuration)"
		let platformsString =  " --platform \(platforms.flatMap({ Optional($0.rawValue) }).joined(separator: " "))"
		let cacheBuildString =  isEnableCacheBuilds ? " --cache-builds" : ""
		let newResolverString =  isEnableCacheBuilds ? " --new-resolver" : ""
		let verboseString = isEnableVerbose ? " --verbose" : ""
		let sshString = isUsingSSH ? " --use-ssh" : ""
		let submodulesString = isUsingSSH ? " --use-submodules" : ""

		return "\(configurationString)\(cacheBuildString)\(platformsString)\(newResolverString)\(verboseString)\(sshString)\(submodulesString)"
	}
}
extension Configuration {
	func uniqueDependency(for dependency: Dependency) -> Dependency {
		var value = dependency
		let name = dependency.name
		if let old = totalDependencies[name] {
			if old.isLocalProject == false, dependency.isLocalProject == true {
				totalDependencies[name] = dependency
			} else {
				value = old
			}
		} else {
			totalDependencies[name] = dependency
		}
		return value
	}
	
	func replaceOverrideDependencies(for dependencies: UnsafeMutablePointer<[Dependency: VersionSpecifier]>){
		let value = dependencies.pointee
		var copyDependencies = value
		for (dependency, version) in value {
			let name = dependency.name
			if let overrideRepo = overridableDependencies[name], overrideRepo != dependency {
				copyDependencies[dependency] = nil
				copyDependencies[overrideRepo] = version
			}
		}
		dependencies.pointee = copyDependencies
	}
}
extension Configuration: CustomStringConvertible {
	public var description: String {
		return """
		
  Config {
	isEnableCacheBuilds: \(isEnableCacheBuilds),
	configuration: \(configuration),
	isEnableNewResolver: \(isEnableNewResolver),
	isEnableVerbose: \(isEnableVerbose),
	isUsingSSH: \(isUsingSSH)
	isUsingSubmodules: \(isUsingSubmodules)
	platforms:\(platforms),
	skippableDepencies:\(skippableDependencies),
	overridableDepencies:\(overridableDependencies)
  }
		
"""
	}
}
/*
#cache-builds: true/false, default false
#verbose: true/false, default false
#configuration: Release/Debug or other
#new-resolver: true/false, default false
#use-ssh: true/false, default false
#use-submodules: true/false, default false
#platform: all/macOS/iOS/watchOS/tvOS
#skip Alamofire,Alamofire.xcworkspace,Alamofire iOS
#override Alamofire,../Alamofire
*/
extension Configuration {
	public enum Key: String {
		case verbose = "#verbose:"
		case configuration = "#configuration:"
		case newResolver = "#new-resolver:"
		case useSSH = "#use-ssh:"
		case useSubmodules = "#use-submodules:"
		case cacheBuilds = "#cache-builds:"
		case platforms = "#platforms:"
		case skip = "#skip:"
		case override = "#override:"
		
		func bool(from line: String) -> Bool {
			let trimLine = line.replacingOccurrences(of: rawValue, with: "").trim.lowercased()
			return trimLine == "true"
		}
	}
	
	public struct SkippableDepency {
		public let name: String
		public let scheme: String?
		public let workspaceOrProject: String?
	}
}


extension Platform {
	static func from(_ raw: String) -> Platform? {
		let lowercasedRaw = raw.lowercased()
		let mac = ["osx", "mac", "macos"]
		switch lowercasedRaw {
		case "ios": return .iOS
		case "watchos": return .watchOS
		case "tvos": return .tvOS
		default:
			if mac.contains(lowercasedRaw) { return .macOS }
			return nil
		}
	}
}
extension Array {
	subscript(c_safe index: Int) -> Element? {
		return indices ~= index ? self[index] : nil
	}
}
extension String {
	var trim: String { return trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
	func hasPrefix<T: RawRepresentable>(_ key: T) -> Bool where T.RawValue == String {
		return hasPrefix(key.rawValue)
	}
}

extension Dependency {
	public var isLocalProject: Bool {
		switch self {
		case .git(let url):
			let urlString = url.urlString
			if urlString.hasPrefix("file://")
				|| urlString.hasPrefix("/") // "/path/to/..."
				|| urlString.hasPrefix(".") // "./path/to/...", "../path/to/..."
				|| urlString.hasPrefix("~") // "~/path/to/..."
				|| !urlString.contains(":") // "path/to/..." with avoiding "git@github.com:owner/name"
			{ return true }
			return false
		default: return false
		}
	}
}
