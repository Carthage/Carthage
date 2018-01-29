import CarthageKit
import Commandant
import Foundation
import ReactiveSwift
import ReactiveTask
import Result

setlinebuf(stdout)

guard ensureGitVersion().first()?.value == true else {
	fputs("Carthage requires git \(carthageRequiredGitVersion) or later.\n", stderr)
	exit(EXIT_FAILURE)
}

if let remoteVersion = remoteVersion(), CarthageKitVersion.current.value < remoteVersion {
	fputs("Please update to the latest Carthage version: \(remoteVersion). You currently are on \(CarthageKitVersion.current.value)" + "\n", stderr)
}

if let carthagePath = Bundle.main.executablePath {
	setenv("CARTHAGE_PATH", carthagePath, 0)
}

Configuration.shared.readConfig()
var golbalColorOption: ColorOptions?

let registry = CommandRegistry<CarthageError>()
registry.register(ArchiveCommand())
registry.register(BootstrapCommand())
registry.register(BuildCommand())
registry.register(CheckoutCommand())
registry.register(CopyFrameworksCommand())
registry.register(FetchCommand())
registry.register(OutdatedCommand())
registry.register(UpdateCommand())
registry.register(VersionCommand())

let helpCommand = HelpCommand(registry: registry)
registry.register(helpCommand)

let start = CFAbsoluteTimeGetCurrent()
registry.main(defaultVerb: helpCommand.verb, completionHandler: {
	let cost = CFAbsoluteTimeGetCurrent() - start
	let time = String(format: "%.2f", cost)
	guard let prefix = golbalColorOption?.formatting.bulletin("***"),
		let t = golbalColorOption?.formatting.path("\(time)s") else { return }
	carthage.println(prefix + "🍺 Success, time cost: " + t)
}, errorHandler: { fputs($0.description + "\n", stderr) })


