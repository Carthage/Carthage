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
import LlamaKit
import ReactiveTask

let registry = CommandRegistry()
registry.register(BootstrapCommand())
registry.register(BuildCommand())
registry.register(CheckoutCommand())
registry.register(CopyFrameworksCommand())
registry.register(FetchCommand())
registry.register(UpdateCommand())
registry.register(VersionCommand())

let helpCommand = HelpCommand(registry: registry)
registry.register(helpCommand)

registry.main(defaultCommand: helpCommand) { error in
	let errorDescription = (error.domain == CarthageErrorDomain || error.domain == CommandantErrorDomain || error.domain == ReactiveTaskError.domain ? error.localizedDescription : error.description)
	fputs("\(errorDescription)\n", stderr)
}
