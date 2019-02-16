import Foundation

extension URL {
    internal var schemeIsValid: Bool {
        return scheme == "file" || scheme == "https"
    }
    internal static var validSchemesMessage: String {
        return "file or https"
    }
}
