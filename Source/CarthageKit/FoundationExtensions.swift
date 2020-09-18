
import Foundation

extension Collection where Element: Hashable {
    
    func unique() -> [Element] {
        var set = Set<Element>(minimumCapacity: count)

        return filter {
            return set.insert($0).inserted
        }
    }
}

extension FileManager {
    
    public func allDirectories(at directoryURL: URL, ignoringExtensions: Set<String> = []) -> [URL] {
        func isDirectory(at url: URL) -> Bool {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true
        }
        
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard
            directoryURL.isFileURL,
            isDirectory(at: directoryURL),
            let enumerator = self.enumerator(at: directoryURL, includingPropertiesForKeys: keys, options: options)
        else {
            return []
        }
        
        var result: [URL] = [directoryURL]

        for url in enumerator {
            if let url = url as? URL, isDirectory(at: url) {
                if !url.pathExtension.isEmpty && ignoringExtensions.contains(url.pathExtension) {
                    enumerator.skipDescendants()
                } else {
                    result.append(url)
                }
            }
        }
        
        return result.map { $0.standardizedFileURL }
    }
}
