import Foundation
import ReactiveSwift
import Result

public struct BuiltProductInfo {
    
    var swiftToolchainVersion: String
    var productUrl: URL
    var commitish: String?
    var fileNames: [String] = []
    
    private var destinationDirectoryURL: URL {
        return productUrl.deletingLastPathComponent()
    }
    private var productFileName: String {
        return productUrl.lastPathComponent
    }
    
    func withCommitish(_ commitish: String) -> BuiltProductInfo {
        var copy = self
        copy.commitish = commitish
        return copy
    }
    
    func addingFile(_ fileUrl: URL) -> BuiltProductInfo {
        var copy = self
        copy.fileNames.append(fileUrl.lastPathComponent)
        return copy
    }
    
    var asFile: BuiltProductInfoFile {
        return BuiltProductInfoFile(swiftToolchainVersion: swiftToolchainVersion,
                                    productFileName: productFileName,
                                    commitish: commitish,
                                    fileNames: fileNames.sorted())
    }
    
    func writeJSONFile() -> Result<(), CarthageError> {
        return Result(at: destinationDirectoryURL, attempt: {
            let metadataFileURL = $0
                .appendingPathComponent(".\(productFileName)")
                .appendingPathExtension("builtProductInfo")
            let encoder = JSONEncoder()
            if #available(OSX 10.13, *) {
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            } else {
                encoder.outputFormatting = [.prettyPrinted]
            }
            let jsonData = try encoder.encode(self.asFile)
            try jsonData.write(to: metadataFileURL, options: .atomic)
        })
    }
}

public struct BuiltProductInfoFile: Codable {
    var swiftToolchainVersion: String?
    var productFileName: String?
    var commitish: String?
    var fileNames: [String] = []
}

public func writeBuiltProductInfoJSONFile(builtProductInfo: BuiltProductInfo) -> SignalProducer<(), CarthageError> {
    return SignalProducer<(), CarthageError> { () -> Result<(), CarthageError> in
        return builtProductInfo.writeJSONFile()
    }
}

public func addCommitish(commitish: String, to builtProductInfos: [BuiltProductInfo]) -> SignalProducer<[BuiltProductInfo], CarthageError> {
    return SignalProducer<[BuiltProductInfo], CarthageError> { () -> Result<[BuiltProductInfo], CarthageError> in
        return Result(catching: {
            return builtProductInfos.map {
                return $0.withCommitish(commitish)
            }
        })
    }
}
