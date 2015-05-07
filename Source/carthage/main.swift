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
import Result
import ReactiveTask

let registry = CommandRegistry<CarthageError>()
registry.register(ArchiveCommand())
registry.register(BootstrapCommand())
registry.register(BuildCommand())
registry.register(CheckoutCommand())
registry.register(CopyFrameworksCommand())
registry.register(FetchCommand())
registry.register(UpdateCommand())
registry.register(VersionCommand())

let helpCommand = HelpCommand(registry: registry)
registry.register(helpCommand)

registry.main(defaultVerb: helpCommand.verb) { error in
	fputs(error.description + "\n", stderr)
}
