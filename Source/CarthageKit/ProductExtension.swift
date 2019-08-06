import Foundation
import Result
import XCDBLD
import ReactiveSwift

/// Describes the type of packages file extensions
public enum ProductExtension: String, CaseIterable {
	/// A .framework package.
	case framework = "framework"
	
	/// A .action package.
	case action = "action"
	
	/// A .bundle package.
	case bundle = "bundle"
	
	/// A .kext package.
	case kext = "kext"
	
	/// A .mdimporter package.
	case mdimporter = "mdimporter"
	
	/// A .metallib package.
	case metallib = "metallib"
	
	/// A .plugin package.
	case plugin = "plugin"
	
	/// A .prefPane package.
	case prefPane = "prefPane"
	
	/// A .qlgenerator package.
	case qlgenerator = "qlgenerator"
	
	/// A .saver package.
	case saver = "saver"
	
	/// A .xpc package.
	case xpc = "xpc"
	
	public static let supportedExtensions: [ProductExtension] = ProductExtension.allCases
	
	/// Attempts to parse a product extension
	public static func from(string: String) -> Result<ProductExtension, CarthageError> {
		return Result(self.init(rawValue: string), failWith: .parseError(description: "unexpected product extension type \"\(string)\""))
	}
	
	/// Check if string is one of the supported extensions
	public static func isSupportedExtension(_ string: String) -> Bool {
		return (self.init(rawValue: string) != nil)
	}
}

/// Enumerate all supported platforms and framework extensions (e.g., .framework, .qlgenerator, etc.).
/// Yield `path-to-framework`, `TARGET_NAME.EXT`
public func enumerateSupportedFrameworks(
	target: String,
	inDirectory: URL,
	isBuildDirectory: Bool = false,
	allowedPlatforms: [Platform] = Platform.supportedPlatforms,
	allowedExtensions: [ProductExtension] = ProductExtension.supportedExtensions
	) -> SignalProducer<(path: URL, name: String), CarthageError> {
	
	return SignalProducer(allowedPlatforms)
		.filterMap { platform -> SignalProducer<(path: URL, name: String), CarthageError> in
			let absoluteURL = inDirectory
				.appendingPathComponent(isBuildDirectory ? platform.rawValue : platform.relativePath)
				.resolvingSymlinksInPath()
				.appendingPathComponent(target, isDirectory: false)
			return SignalProducer(allowedExtensions)
				.map { absoluteURL.appendingPathExtension($0.rawValue) }
				.filter { FileManager.default.fileExists(atPath: $0.path) }
				.map { ($0.deletingLastPathComponent(), $0.lastPathComponent) }
		}
		.flatten(.merge)
}
