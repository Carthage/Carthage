//
//  Checkout.swift
//  Carthage
//
//  Created by Alan Rogers on 11/10/2014.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import CarthageKit
import Commandant
import Foundation
import LlamaKit
import ReactiveCocoa

public struct CheckoutCommand: CommandType {
	public let verb = "checkout"
	public let function = "Check out the project's dependencies"

	public func run(mode: CommandMode) -> Result<()> {
		return ColdSignal.fromResult(CheckoutOptions.evaluate(mode))
			.map { self.checkoutWithOptions($0) }
			.merge(identity)
			.wait()
	}

	/// Checks out dependencies with the given options.
	public func checkoutWithOptions(options: CheckoutOptions) -> ColdSignal<()> {
		return ColdSignal.fromResult(options.loadProject())
			.map { $0.checkoutLockedDependencies() }
			.merge(identity)
	}
}

public struct CheckoutOptions: OptionsType {
	public let directoryPath: String
	public let useSSH: Bool

	public static func create(useSSH: Bool)(directoryPath: String) -> CheckoutOptions {
		return self(directoryPath: directoryPath, useSSH: useSSH)
	}

	public static func evaluate(m: CommandMode) -> Result<CheckoutOptions> {
		return create
			<*> m <| Option(key: "use-ssh", defaultValue: false, usage: "use SSH for downloading GitHub repositories")
			<*> m <| Option(defaultValue: NSFileManager.defaultManager().currentDirectoryPath, usage: "the directory containing the Carthage project")
	}

	/// Attempts to load the project referenced by the options, and configure it
	/// accordingly.
	public func loadProject() -> Result<Project> {
		if let directoryURL = NSURL.fileURLWithPath(self.directoryPath, isDirectory: true) {
			return Project.loadFromDirectory(directoryURL).map { project in
				project.preferHTTPS = !self.useSSH
				project.projectEvents.observe(ProjectEventSink())
				return project
			}
		} else {
			return failure(CarthageError.InvalidArgument(description: "Invalid project path: \(directoryPath)").error)
		}
	}
}

/// Logs project events put into the sink.
private struct ProjectEventSink: SinkType {
	mutating func put(event: ProjectEvent) {
		switch event {
		case let .Cloning(project):
			carthage.println("*** Cloning \(project.name)")

		case let .Fetching(project):
			carthage.println("*** Fetching \(project.name)")

		case let .CheckingOut(project, revision):
			carthage.println("*** Checking out \(project.name) at \"\(revision)\"")
		}
	}
}
