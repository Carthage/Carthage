import Foundation

extension URL {
    internal func validateScheme(allowHTTP: Bool = false) -> Bool {
        return scheme == "file" || scheme == "https" || (scheme == "http" && allowHTTP)
    }
    internal static var validSchemesMessage: String {
        return "file, https or http if allowed"
    }
}
