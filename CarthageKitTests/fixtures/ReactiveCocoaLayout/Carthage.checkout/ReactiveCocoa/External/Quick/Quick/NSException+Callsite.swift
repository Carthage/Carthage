import Foundation

let FilenameKey = "SenTestFilenameKey"
let LineNumberKey = "SenTestLineNumberKey"

extension NSException {
    var qck_callsite: Callsite? {
        if let info: NSDictionary = userInfo {
            if let file = info[FilenameKey] as? String {
                if let line = info[LineNumberKey] as? Int {
                    return Callsite(file: file, line: line)
                }
            }
        }

        return nil
    }
}
