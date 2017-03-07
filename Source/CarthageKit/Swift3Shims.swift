import Foundation

#if swift(>=3)
	internal extension URL {
		// https://github.com/apple/swift-corelibs-foundation/blob/swift-3.0.1-RELEASE/Foundation/URL.swift#L607-L619
		var carthage_path: String {
			return path
		}

		var carthage_lastPathComponent: String {
			return lastPathComponent
		}
	}
#endif
