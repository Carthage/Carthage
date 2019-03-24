
import Foundation
import Result
import ReactiveSwift
import Tentacle
import XCDBLD
import ReactiveTask

public final class InputFilesInferrer {
    
    typealias LinkedFrameworksResolver = (URL) -> Result<[String], CarthageError>
    
    var executableResolver: (URL) -> URL? = { Bundle(url: $0)?.executableURL }
    
    private let builtFrameworks: SignalProducer<URL, CarthageError>
    private let linkedFrameworksResolver: LinkedFrameworksResolver
    
    init(builtFrameworks: SignalProducer<URL, CarthageError>, linkedFrameworksResolver: @escaping LinkedFrameworksResolver) {
        self.builtFrameworks = builtFrameworks
        self.linkedFrameworksResolver = linkedFrameworksResolver
    }

    public convenience init(projectDirectory: URL, platform: Platform) {
        let searchDirectory = projectDirectory.appendingPathComponent(platform.relativePath, isDirectory: true)
        self.init(builtFrameworks: frameworksInDirectory(searchDirectory), linkedFrameworksResolver: linkedFrameworks(for:))
    }

    public func inputFiles(for executableURL: URL, userInputFiles: SignalProducer<URL, CarthageError>) -> SignalProducer<URL, CarthageError> {
        let userFrameworksMap = userInputFiles.reduce(into: [String: URL]()) { (map, frameworkURL) in
            let name = frameworkURL.deletingPathExtension().lastPathComponent
            map[name] = frameworkURL
        }

        let builtFrameworksMap = builtFrameworks
            .filter { url in
                // We need to filter out any static frameworks to not accidentally copy then for the dynamically linked ones.
                let components = url.pathComponents
                let staticFolderIndex = components.index(components.endIndex, offsetBy: -2)
                return staticFolderIndex >= 0 && components[staticFolderIndex] != FrameworkType.staticFolderName
            }
            .reduce(into: [String: URL]()) { (map, frameworkURL) in
                let name = frameworkURL.deletingPathExtension().lastPathComponent
                map[name] = frameworkURL
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

    /// Finds Carthage's frameworks that are linked against a given executable.
    ///
    /// - Parameters:
    ///   - executableURL: Path to a executable of the Project. See `xcodebuild` settings `TARGET_BUILD_DIR` and `EXECUTABLE_PATH` for more info.
    ///   - platform: Platform of the executable.
    /// - Returns: Stream of Path for each linked framework for a given `platform` that was build by Carthage.
}

/// Invokes otool -L for a given executable URL.
///
/// - Parameter executableURL: URL to a valid executable.
/// - Returns: Array of the Shared Library ID that are linked against given executable (`Alamofire`, `Realm`, etc).
/// System libraries and dylibs are omited.
internal func linkedFrameworks(for executable: URL) -> Result<[String], CarthageError> {
    return Task("/usr/bin/xcrun", arguments: ["otool", "-L", executable.path.spm_shellEscaped()])
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
    guard let regex = try? NSRegularExpression(pattern: "[\\w\\.]+\\.framework\\/([\\w\\.]+)") else {
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

