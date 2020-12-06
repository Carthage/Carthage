import Foundation
import Result
import ReactiveSwift
import ReactiveTask

/// Represents version and build version of an Xcode.
public struct XcodeVersion {
	public let version: String
	public let buildVersion: String

	private init(version: String, buildVersion: String) {
		self.version = version
		self.buildVersion = buildVersion
	}

	internal init?(xcodebuildOutput: String) {
		let range = NSRange(xcodebuildOutput.startIndex..., in: xcodebuildOutput)
		guard let match = XcodeVersion.regex.firstMatch(in: xcodebuildOutput, range: range) else {
			return nil
		}

		let version = String(xcodebuildOutput[Range(match.range(at: 1), in: xcodebuildOutput)!])
		let buildVersion = String(xcodebuildOutput[Range(match.range(at: 2), in: xcodebuildOutput)!])

		self.init(version: version, buildVersion: buildVersion)
	}

	// swiftlint:disable next force_try
	private static let regex = try! NSRegularExpression(pattern: "Xcode ([0-9.]+)\\nBuild version (.+)")

	public static func make() -> XcodeVersion? {
		let task = Task("/usr/bin/xcrun", arguments: ["xcodebuild", "-version"])
		return task.launch()
			.ignoreTaskData()
			.map { String(data: $0, encoding: .utf8)! }
			.flatMap(.concat) { output -> SignalProducer<XcodeVersion, TaskError> in
				if let xcodeVersion = XcodeVersion(xcodebuildOutput: output) {
					return .init(value: xcodeVersion)
				} else {
					return .empty
				}
			}
			.single()?.value
	}
}
