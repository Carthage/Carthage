import Foundation

#if swift(>=3)
	import Result

	internal extension URL {
		var carthage_absoluteString: String {
			return absoluteString
		}

		// https://github.com/apple/swift-corelibs-foundation/blob/swift-3.0.1-RELEASE/Foundation/URL.swift#L607-L619
		var carthage_path: String {
			return path
		}

		var carthage_lastPathComponent: String {
			return lastPathComponent
		}

		var carthage_pathComponents: [String] {
			return pathComponents
		}
	}

	// MARK: - Result

	internal extension Result {
		func fanout<R: ResultProtocol>(_ other: @autoclosure () -> R) -> Result<(Value, R.Value), Error> where Error == R.Error {
			return self.flatMap { left in other().map { right in (left, right) } }
		}
	}
#endif
