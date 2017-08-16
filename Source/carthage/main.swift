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

registry.main(defaultVerb: helpCommand.verb) { error in
	fputs(error.description + "\n", stderr)
}
