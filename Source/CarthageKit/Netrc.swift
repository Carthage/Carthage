import Foundation
import Result

internal struct NetrcMachine {
    let name: String
    let login: String
    let password: String
}

internal struct Netrc {
    
    enum NetrcError: Error {
        case fileNotFound(URL)
        case unreadableFile(URL)
        case machineNotFound
        case missingToken(String)
        case missingValueForToken(String)
    }
    
    static func load(from fileURL: URL = URL(fileURLWithPath: "\(NSHomeDirectory())/.netrc")) -> Result<[NetrcMachine], NetrcError> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .failure(NetrcError.fileNotFound(fileURL)) }
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else { return .failure(NetrcError.unreadableFile(fileURL)) }
        
        return Result(catching: { try String(contentsOf: fileURL, encoding: .utf8) })
            .flatMap { Netrc.from($0) }
    }
    
    static func from(_ content: String) -> Result<[NetrcMachine], NetrcError> {
        let tokens = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter({ $0 != "" })
        
        var machines: [NetrcMachine] = []
        
        let machineTokens = tokens.split { $0 == "machine" }
        guard tokens.contains("machine"), machineTokens.count > 0 else { return .failure(NetrcError.machineNotFound) }
        
        for machine in machineTokens {
            let values = Array(machine)
            guard let name = values.first else { continue }
            guard let login = values["login"] else { return .failure(NetrcError.missingValueForToken("login")) }
            guard let password = values["password"] else { return .failure(NetrcError.missingValueForToken("password")) }
            machines.append(NetrcMachine(name: name, login: login, password: password))
        }
        
        guard machines.count > 0 else { return .failure(NetrcError.machineNotFound) }
        return .success(machines)
    }
}

fileprivate extension Array where Element == String {
    subscript(_ token: String) -> String? {
        guard let tokenIndex = firstIndex(of: token),
            count > tokenIndex,
            !["machine", "login", "password"].contains(self[tokenIndex + 1]) else {
                return nil
        }
        return self[tokenIndex + 1]
    }
}
