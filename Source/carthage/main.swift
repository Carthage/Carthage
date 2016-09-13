//
//  main.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Commandant
import Foundation
import ReactiveCocoa
import ReactiveTask
import Result

setlinebuf(stdout)

guard ensureGitVersion().first()?.value == true else {
	fputs("Carthage requires git \(CarthageRequiredGitVersion) or later.\n", stderr)
	exit(EXIT_FAILURE)
}

if let carthagePath = NSBundle.mainBundle().executablePath {
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
