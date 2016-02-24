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

guard ensureGitVersion().first()?.value == true else {
	fputs("Carthage requires git \(CarthageRequiredGitVersion) or later.\n", stderr)
	exit(EXIT_FAILURE)
}

let networkClient = URLSessionNetworkClient(urlSession: NSURLSession.sharedSession())

let registry = CommandRegistry<CarthageError>()
registry.register(ArchiveCommand())
registry.register(BootstrapCommand(networkClient: networkClient))
registry.register(BuildCommand(networkClient: networkClient))
registry.register(CheckoutCommand(networkClient: networkClient))
registry.register(CopyFrameworksCommand())
registry.register(FetchCommand())
registry.register(UpdateCommand(networkClient: networkClient))
registry.register(VersionCommand())

let helpCommand = HelpCommand(registry: registry)
registry.register(helpCommand)

registry.main(defaultVerb: helpCommand.verb) { error in
	fputs(error.description + "\n", stderr)
}
