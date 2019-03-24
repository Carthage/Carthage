
import Foundation
import Result
import ReactiveSwift
import Tentacle
import XCDBLD
import ReactiveTask

public final class InputFilesInferrer {
    
    typealias LinkedFrameworksResolver = (URL) -> Result<[String], CarthageError>
    
    private let builtFrameworksEnumerator: SignalProducer<URL, CarthageError>
    private let linkedFrameworksResolver: LinkedFrameworksResolver
    
    init(builtFrameworksEnumerator: SignalProducer<URL, CarthageError>, linkedFrameworksResolver: @escaping LinkedFrameworksResolver) {
        self.builtFrameworksEnumerator = builtFrameworksEnumerator
        self.linkedFrameworksResolver = linkedFrameworksResolver
    }

    public convenience init(projectDirectory: URL, platform: Platform) {
        let searchDirectory = projectDirectory.appendingPathComponent(platform.relativePath, isDirectory: true)
        self.init(builtFrameworksEnumerator: frameworksInDirectory(searchDirectory), linkedFrameworksResolver: linkedFrameworks(for:))
    }

    func inputFiles(for executableURL: URL, userInputFiles: SignalProducer<URL, CarthageError>) -> SignalProducer<URL, CarthageError> {
        let builtFrameworksMap = builtFrameworksEnumerator
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
        
        return builtFrameworksMap.map { map in
            return URL(fileURLWithPath: "/")
        }

//        return sharedLinkedFrameworks(for: executableURL).flatMap(.latest) { frameworks -> SignalProducer<String, CarthageError> in
//            if frameworks.isEmpty {
//                return .empty
//            }
//
//            return existingFrameworksMap.flatMap(.latest) {  builtFrameworks -> SignalProducer<String, CarthageError> in
//                return SignalProducer(frameworks).filterMap { builtFrameworks[$0]?.path }
//            }
//        }
    }
    
//    private func resolveLinkedFrameworks(using userInputFiles: [String], builtFrameworksMap: [String: URL]) -> SignalProducer<String, CarthageError> {
//        var collectedFrameworksMap: [String: URL] = [:]
//
//
//        // collect executable frameworks
//        // for each entry collect nested frameworks
//        // substituting paths from user input files whenever possible
//    }
    
//    private func resolveLinkedFrameworks(
//        at url: URL,
//        userFrameworksMap: [String: URL],
//        builtFrameworksMap: [String: URL],
//        accumulator: [String: URL]
//    ) throws {
//        accumulator[url.deletingPathExtension().lastPathComponent] = url
//
//        let linkedFrameworks = linkedFrameworksResolver(url)
//    }
    
//    private func linkedFrameworks(using userInputFiles: [String]) -> [String] {
//
//    }

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

