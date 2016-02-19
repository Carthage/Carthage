import Foundation

public protocol FileManager {
	var currentDirectoryPath: String { get }

	func fileExistsAtPath(path: String) -> Bool
}

extension NSFileManager: FileManager {}
