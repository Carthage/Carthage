import Foundation
import ReactiveSwift
import XCDBLD
import Result
import ReactiveTask

final class FrameworkInformationProvider: FrameworkInformationProviding {
	/// Sends the URLs of the bcsymbolmap files that match the given framework and are
	/// located somewhere within the given directory.
	func BCSymbolMapsForFramework(_ frameworkURL: URL, inDirectoryURL directoryURL: URL) -> SignalProducer<URL, CarthageError> {
		return UUIDsForFramework(frameworkURL)
			.flatMap(.merge) { uuids -> SignalProducer<URL, CarthageError> in
				if uuids.isEmpty {
					return .empty
				}
				func filterUUIDs(_ signal: Signal<URL, CarthageError>) -> Signal<URL, CarthageError> {
					var remainingUUIDs = uuids
					let count = remainingUUIDs.count
					return signal
						.filter { fileURL in
							let basename = fileURL.deletingPathExtension().lastPathComponent
							if let fileUUID = UUID(uuidString: basename) {
								return remainingUUIDs.remove(fileUUID) != nil
							} else {
								return false
							}
					}
					.take(first: count)
				}
				return self.BCSymbolMapsInDirectory(directoryURL)
					.lift(filterUUIDs)
		}
	}

	/// Sends the URL to each bcsymbolmap found in the given directory.
	internal func BCSymbolMapsInDirectory(_ directoryURL: URL) -> SignalProducer<URL, CarthageError> {
		return filesInDirectory(directoryURL)
			.filter { url in url.pathExtension == "bcsymbolmap" }
	}

	/// Sends the platform specified in the given Info.plist.
	func platformForFramework(_ frameworkURL: URL) -> SignalProducer<Platform, CarthageError> {
		return SignalProducer(value: frameworkURL)
			// Neither DTPlatformName nor CFBundleSupportedPlatforms can not be used
			// because Xcode 6 and below do not include either in macOS frameworks.
			.attemptMap { url -> Result<String, CarthageError> in
				let bundle = Bundle(url: url)

				func readFailed(_ message: String) -> CarthageError {
					let error = Result<(), NSError>.error(message)
					return .readFailed(frameworkURL, error)
				}

				func sdkNameFromExecutable() -> String? {
					guard let executableURL = bundle?.executableURL else {
						return nil
					}

					let task = Task("/usr/bin/xcrun", arguments: ["otool", "-lv", executableURL.path])

					let sdkName: String? = task.launch(standardInput: nil)
						.ignoreTaskData()
						.map { String(data: $0, encoding: .utf8) ?? "" }
						.filter { !$0.isEmpty }
						.flatMap(.merge) { (output: String) -> SignalProducer<String, NoError> in
							output.linesProducer
					}
					.filter { $0.contains("LC_VERSION") }
					.take(last: 1)
					.map { lcVersionLine -> String? in
						let sdkString = lcVersionLine.split(separator: "_")
							.last
							.flatMap(String.init)
							.flatMap { $0.lowercased() }

						return sdkString
					}
					.skipNil()
					.single()?
					.value

					return sdkName
				}

				// Try to read what platfrom this binary is for. Attempt in order:
				// 1. Read `DTSDKName` from Info.plist.
				//    Some users are reporting that static frameworks don't have this key in the .plist,
				//    so we fall back and check the binary of the executable itself.
				// 2. Read the LC_VERSION_<PLATFORM> from the framework's binary executable file
				if let sdkNameFromBundle = bundle?.object(forInfoDictionaryKey: "DTSDKName") as? String {
					return .success(sdkNameFromBundle)
				} else if let sdkNameFromExecutable = sdkNameFromExecutable() {
					return .success(sdkNameFromExecutable)
				} else {
					return .failure(readFailed("could not determine platform neither from DTSDKName key in plist nor from the framework's executable"))
				}
		}
			// Thus, the SDK name must be trimmed to match the platform name, e.g.
			// macosx10.10 -> macosx
			.map { (sdkName: String) in sdkName.trimmingCharacters(in: CharacterSet.letters.inverted) }
			.attemptMap { platform in SDK.from(string: platform).map { $0.platform } }
	}
}
