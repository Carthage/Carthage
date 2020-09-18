
import Foundation
import Result
import ReactiveSwift
import Tentacle
import XCDBLD
import ReactiveTask

public final class InputFilesInferrer {
    
    typealias LinkedFrameworksResolver = (URL) -> Result<[String], CarthageError>
    
    /// For test-use only
    var executableResolver: (URL) -> URL? = { Bundle(url: $0)?.executableURL }
    
    /// For test-use only
    var builtFrameworkFilter: (URL) -> Bool = { url in
        if
            let executableURL = Bundle(url: url)?.executableURL,
            let header = MachHeader.headers(forMachOFileAtUrl: executableURL).single()?.value
        {
            return header.fileType == MH_DYLIB
        }
        return false
    }
    
    private let builtFrameworks: SignalProducer<URL, CarthageError>
    private let linkedFrameworksResolver: LinkedFrameworksResolver
    
    // MARK: - Init
    
    init(builtFrameworks: SignalProducer<URL, CarthageError>, linkedFrameworksResolver: @escaping LinkedFrameworksResolver) {
        self.builtFrameworks = builtFrameworks
        self.linkedFrameworksResolver = linkedFrameworksResolver
    }

    public convenience init(projectDirectory: URL, platform: Platform, frameworkSearchPaths: [URL]) {
        let allFrameworkSearchPath = InputFilesInferrer.allFrameworkSearchPaths(
            forProjectIn: projectDirectory,
            platform: platform,
            frameworkSearchPaths: frameworkSearchPaths
        )
        let enumerator = SignalProducer(allFrameworkSearchPath).flatMap(.concat, frameworksInDirectory)
        
        self.init(builtFrameworks: enumerator, linkedFrameworksResolver: linkedFrameworks(for:))
    }
    
    // MARK: - Inferring

    public func inputFiles(for executableURL: URL, userInputFiles: SignalProducer<URL, CarthageError>) -> SignalProducer<URL, CarthageError> {
        let userFrameworksMap = userInputFiles.reduce(into: [String: URL]()) { (map, frameworkURL) in
            let name = frameworkURL.deletingPathExtension().lastPathComponent
            map[name] = frameworkURL
        }

        let builtFrameworksMap = builtFrameworks
            .filter(builtFrameworkFilter)
            .reduce(into: [String: URL]()) { (map, frameworkURL) in
                let name = frameworkURL.deletingPathExtension().lastPathComponent
                // Framework potentially can be presented in multiple directories from FRAMEWORK_SEARCH_PATHS.
                // We're only interested in the first occurrence to preserve order of the paths.
                if map[name] == nil {
                    map[name] = frameworkURL
                }
            }
        
        return SignalProducer.combineLatest(userFrameworksMap, builtFrameworksMap)
            .flatMap(.latest) { userFrameworksMap, builtFrameworksMap -> SignalProducer<URL, CarthageError> in
                let availableFrameworksMap = userFrameworksMap.merging(builtFrameworksMap) { (lhs, rhs) in
                    // user's framework path always takes precedence over default Carthage's path.
                    return lhs
                }
                
                if availableFrameworksMap.isEmpty {
                    return .empty
                }
                
                return SignalProducer(result: self.resolveFrameworks(at: executableURL, frameworksMap: availableFrameworksMap))
                    .flatten()
                    .filter { url in
                        // We have to omit paths already specified by User.
                        // Can't use direct URLs comparison, because it is not guaranteed that same framework will have
                        // same URL all the time. i.e. '/A.framework/' and '/A.framework' will lead to the same result but are not equal.
                        let name = url.deletingPathExtension().lastPathComponent
                        return userFrameworksMap[name] == nil
                    }
            }
    }
    
    private func resolveFrameworks(at executableURL: URL, frameworksMap: [String: URL]) -> Result<[URL], CarthageError> {
        var resolvedFrameworks: Set<String> = []
        do {
            try collectFrameworks(at: executableURL, accumulator: &resolvedFrameworks, frameworksMap: frameworksMap)
        } catch let error as CarthageError {
            return .failure(error)
        } catch {
            return .failure(CarthageError.internalError(description: "Failed to infer linked frameworks"))
        }
        
        return .success(resolvedFrameworks.compactMap { frameworksMap[$0] })
    }
    
    private func collectFrameworks(at executableURL: URL, accumulator: inout Set<String>, frameworksMap: [String: URL]) throws {
        let name = executableURL.deletingPathExtension().lastPathComponent
        if !accumulator.insert(name).inserted {
            return
        }
        
        switch linkedFrameworksResolver(executableURL) {
        case .success(let values):
            let frameworksToCollect = values
                .filter { !accumulator.contains($0) }
                .compactMap { frameworksMap[$0] }
                .compactMap(executableResolver)

            try frameworksToCollect.forEach {
                try collectFrameworks(at: $0, accumulator: &accumulator, frameworksMap: frameworksMap)
            }
            
        case .failure(let error):
            throw error
        }
    }
    
    // MARK: - Utility
    
    static func allFrameworkSearchPaths(forProjectIn directory: URL, platform: Platform, frameworkSearchPaths: [URL]) -> [URL] {
        // Carthage's default framework search path should always be presented. Under rare circumstances
        // framework located at the non-default path can be linked against Carthage's framework.
        // Since we're allowing user to specify only first-level frameworks, App might not link transient framework,
        // therefore FRAMEWORKS_SEARCH_PATHS won't contain Carthage default search path.
        // To prevent such failure we're appending default path at the end.
        let defaultSearchPath = defaultFrameworkSearchPath(forProjectIn: directory, platform: platform)
        // To throw away all duplicating paths.
        // `standardizedFileURL` is needed to normalize paths like `/tmp/search/path` and `/private/tmp/search/path` to
        // make them equal. Otherwise we'll end up having duplicates of the same path. Latter one even might be invalid.
        let result = (frameworkSearchPaths + [defaultSearchPath]).map { $0.standardizedFileURL }.unique()
        return result
    }
    
    static func defaultFrameworkSearchPath(forProjectIn directory: URL, platform: Platform) -> URL {
        return directory.appendingPathComponent(platform.relativePath, isDirectory: true)
    }
    
    /// Maps Xcode's `FRAMEWORK_SEARCH_PATHS` string to an array or file URLs as well as resolves recursive directories.
    ///
    /// - Parameter rawFrameworkSearchPaths: Value of `FRAMEWORK_SEARCH_PATHS`
    /// - Returns: Array of corresponding file URLs.
    public static func frameworkSearchPaths(from rawFrameworkSearchPaths: String) -> [URL] {
        // During expansion of the recursive path we don't want to enumarate over a directories that are known
        // to be used as resources / other xcode-specific files that do not contain any frameworks.
        let ignoredDirectoryExtensions: Set<String> = [
            "app",
            "dSYM",
            "docset",
            "framework",
            "git",
            "lproj",
            "playground",
            "xcassets",
            "scnassets",
            "xcstickers",
            "xcbaseline",
            "xcdatamodel",
            "xcmappingmodel",
            "xcodeproj",
            "xctemplate",
            "xctest",
            "xcworkspace"
        ]
        
        // We can not split by ' ' or by '\n' since it will give us invalid results because of the escaped spaces.
        // To handle this we're replacing escaped spaces by ':' which seems to be the only invalid symbol on macOS,
        // making conversion and then reverting replacement.
        let escapingSymbol = ":"
        return rawFrameworkSearchPaths
            .replacingOccurrences(of: "\\ ", with: escapingSymbol)
            .split(separator: " ")
            .map { $0.replacingOccurrences(of: escapingSymbol, with: " ") }
            .flatMap { path -> [URL] in
                // For recursive paths Xcode adds a "**" suffix. i.e. /search/path turns into a /search/path/**
                // We need to collect all the nested paths to act like an Xcode.
                let recursiveSymbol = "**"
                
                if path.hasSuffix(recursiveSymbol) {
                    let normalizedURL = URL(fileURLWithPath: String(path.dropLast(recursiveSymbol.count)), isDirectory: true)
                    return FileManager.default.allDirectories(at: normalizedURL, ignoringExtensions: ignoredDirectoryExtensions)
                } else {
                    return [URL(fileURLWithPath: path, isDirectory: true)]
                }
            }
            .map { $0.standardizedFileURL }
    }
}

/// Invokes otool -L for a given executable URL.
///
/// - Parameter executableURL: URL to a valid executable.
/// - Returns: Array of the Shared Library ID that are linked against given executable (`Alamofire`, `Realm`, etc).
/// System libraries and dylibs are omited.
internal func linkedFrameworks(for executable: URL) -> Result<[String], CarthageError> {
    return Task("/bin/sh", arguments: ["-c", "/usr/bin/xcrun otool -L '\(executable.path)'"])
        .launch()
        .mapError(CarthageError.taskError)
        .ignoreTaskData()
        .filterMap { data -> String? in
            return String(data: data, encoding: .utf8)
        }
        .map(linkedFrameworks(from:))
        .single() ?? .success([])
}

/// Stripping linked shared frameworks from
/// @rpath/Alamofire.framework/Alamofire (compatibility version 1.0.0, current version 1.0.0)
/// to Alamofire as well as filtering out system frameworks and various dylibs.
/// Static frameworks and libraries won't show up here, so we can ignore them.
///
/// - Parameter input: Output of the otool -L
/// - Returns: Array of Shared Framework IDs.
internal func linkedFrameworks(from input: String) -> [String] {
    // Executable name matches c99 extended identifier.
    // This regex ignores dylibs but we don't need them.
    guard let regex = try? NSRegularExpression(pattern: "\\/([\\w_]+) ") else {
        return []
    }
    return input.components(separatedBy: "\n").compactMap { value in
        let fullNSRange = NSRange(value.startIndex..<value.endIndex, in: value)
        if
            
            let match = regex.firstMatch(in: value, range: fullNSRange),
            match.numberOfRanges > 1,
            match.range(at: 1).length > 0
        {
            return Range(match.range(at: 1), in: value).map { String(value[$0]) }
        }
        return nil
    }
}
