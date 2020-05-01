import Foundation
import ReactiveSwift
import Result
import XCDBLD

public struct FrameworkInfo: Equatable, Hashable {
    
    var sourceURL: URL
    var destinationURL: URL
    var platform: Platform
}

extension Array where Element == FrameworkInfo {

    // Returns the unique pairs in the input array
    // or the duplicate keys by .destinationURL
    func uniqueSourceDestinationPairs() -> Result<[FrameworkInfo], CarthageError> {
        let destinationMap = reduce(into: [FrameworkInfo : [URL]]()) { result, frameworkInfo in
            result[frameworkInfo] = (result[frameworkInfo] ?? []) + [frameworkInfo.sourceURL]
        }
        let dupes = destinationMap.filter { $0.value.count > 1 }
        guard dupes.count == 0 else {
            //TODO: transform dupes to duplicatesInArchive dictionary
            return .failure(CarthageError.duplicatesInArchive(duplicates: CarthageError.DuplicatesInArchive(dictionary: [:])))
        }
        let uniquePairs = destinationMap
            .filter { $0.value.count == 1 }
            .map { $0.key }
        return .success(uniquePairs)
    }
}

extension SignalProducer where Value == Platform, Error == CarthageError {
    
    public func frameworkInfo(sourceURL: URL, directoryURL: URL) -> SignalProducer<FrameworkInfo, CarthageError> {
        /// Constructs the file:// URL at which a given .framework
        /// will be found. Depends on the location of the current project.
        func frameworkURLInCarthageBuildFolder(
            forPlatform platform: Platform,
            frameworkNameAndExtension: String,
            directoryURL: URL
        ) -> Result<URL, CarthageError> {
            guard let lastComponent = URL(string: frameworkNameAndExtension)?.pathExtension,
                lastComponent == "framework" else {
                    return .failure(.internalError(description: "\(frameworkNameAndExtension) is not a valid framework identifier"))
            }

            guard let destinationURLInWorkingDir = platform
                .relativeURL?
                .appendingPathComponent(frameworkNameAndExtension, isDirectory: true) else {
                    return .failure(.internalError(description: "failed to construct framework destination url from \(platform) and \(frameworkNameAndExtension)"))
            }

            return .success(directoryURL
                .appendingPathComponent(destinationURLInWorkingDir.path, isDirectory: true)
                .standardizedFileURL)
        }
        
        return producer.flatMap(.merge) { platform -> SignalProducer<FrameworkInfo, CarthageError> in
            return frameworkURLInCarthageBuildFolder(forPlatform: platform,
                                                     frameworkNameAndExtension: sourceURL.lastPathComponent,
                                                     directoryURL: directoryURL)
                .producer
                .attemptMap { .success(FrameworkInfo(sourceURL: sourceURL, destinationURL: $0, platform: platform)) }
        }
    }
}
