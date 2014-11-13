@objc public class Callsite {
    public let file: String
    public let line: Int

    init(file: String, line: Int) {
        self.file = file
        self.line = line
    }
}
