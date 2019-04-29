import Foundation

internal struct NetrcMachine {
    let name: String
    let login: String
    let password: String
}

internal struct Netrc {
    
    enum NetrcError: Error {
        case fileNotFound(String)
        case unreadableFile(String)
        case machineNotFound
        case missingToken(String)
        case missingValueForToken(String)
    }
    
    static func load(from file: URL = URL(fileURLWithPath: "\(NSHomeDirectory())/.netrc")) throws -> [NetrcMachine] {
        guard FileManager.default.fileExists(atPath: file.path) else { throw NetrcError.fileNotFound(file.path) }
        guard FileManager.default.isReadableFile(atPath: file.path) else { throw NetrcError.unreadableFile(file.path) }
        
        let content = try String(contentsOf: file, encoding: .utf8)
        return try Netrc.load(from: content)
    }
    
    static func load(from content: String) throws -> [NetrcMachine] {
        let tokens = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter({ $0 != "" })
        
        var machines: [NetrcMachine] = []
        
        let machineTokens = tokens.split { $0 == "machine" }
        guard tokens.contains("machine"), machineTokens.count > 0 else { throw NetrcError.machineNotFound }
        
        for machine in machineTokens {
            let values = Array(machine)
            guard let name = values.first else { continue }
            guard let login = values["login"] else { throw NetrcError.missingValueForToken("login") }
            guard let password = values["password"] else { throw NetrcError.missingValueForToken("password") }
            machines.append(NetrcMachine(name: name, login: login, password: password))
        }
        
        guard machines.count > 0 else { throw NetrcError.machineNotFound }
        return machines
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
