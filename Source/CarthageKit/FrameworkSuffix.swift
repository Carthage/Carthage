import Result

/// Framework Suffix
public enum FrameworkSuffix: String {
    /// Framework
    case framework = "framework"

    /// XCFramework
    case xcframework = "xcframework"

    /// Attempts to parse a product type from a string path component
    public static func from(string: String) -> Result<FrameworkSuffix, CarthageError> {
        return Result(self.init(rawValue: string), failWith: .parseError(description: "unexpected framework suffix \"\(string)\""))
    }
}
