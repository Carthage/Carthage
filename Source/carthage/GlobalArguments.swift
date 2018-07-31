import Foundation
import Curry
import Commandant
import Result

struct GlobalOptions: OptionsProtocol {

	let skipRemoteVersionCheck: Bool

	typealias ClientError = NoError

	static func evaluate(_ m: CommandMode) -> Result<GlobalOptions, CommandantError<NoError>> {
		return curry(self.init)
			<*> m <| Option(key: "skip-remote-version-check", defaultValue: false, usage: "avoid checking for version remotely")
	}

	static func consume(globalArguments: inout [String]) -> GlobalOptions {
		let options = GlobalOptions.evaluate(.arguments(ArgumentParser(globalArguments)))
		globalArguments.pop { $0 == "--skip-remote-version-check" }
		return options.value!
	}
}

extension Array {

	@discardableResult
	mutating func pop(where predicate: (Element) -> Bool) -> Element? {
		return index(where: predicate)
			.map { remove(at: $0) }
	}
}
