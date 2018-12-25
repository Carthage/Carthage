/// Error parsing strings into types, used in Scannable protocol
public struct ScannableError: Error, Equatable {
	let message: String
	let currentLine: String?

	public init(message: String, currentLine: String? = nil) {
		self.message = message
		self.currentLine = currentLine
	}
}

extension ScannableError: CustomStringConvertible {
	public var description: String {
		return currentLine.map { "\(message) in line: \($0)" } ?? message
	}
}
