import Foundation
import Result
import ReactiveSwift
import ReactiveTask

#if !swift(>=4)
	extension NSTextCheckingResult {
		fileprivate func range(at idx: Int) -> NSRange {
			return rangeAt(idx)
		}
	}
#endif

public struct XcodeVersion {
	public let version: String
	public let buildVersion: String

	private init(version: String, buildVersion: String) {
		self.version = version
		self.buildVersion = buildVersion
	}

	public static func make() -> XcodeVersion? {
		let task = Task("/usr/bin/xcrun", arguments: ["xcodebuild", "-version"])
		return task.launch()
			.ignoreTaskData()
			.map { String(data: $0, encoding: .utf8)! }
			.flatMap(.concat) { input -> SignalProducer<XcodeVersion, TaskError> in
				// swiftlint:disable next force_try
				let regex = try! NSRegularExpression(pattern: "Xcode ([0-9.]+)\\nBuild version (.+)")
				guard let match = regex.firstMatch(in: input, range: NSRange(location: 0, length: input.utf16.count)) else {
					return .empty
				}

				let nsString = input as NSString
				let version = nsString.substring(with: match.range(at: 1))
				let buildVersion = nsString.substring(with: match.range(at: 2))

				let xcodeVersion = XcodeVersion(version: version, buildVersion: buildVersion)
				return SignalProducer(value: xcodeVersion)
			}
			.single()?.value
	}
}
