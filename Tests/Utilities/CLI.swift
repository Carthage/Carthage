//
//  CLI.swift
//  Carthage
//
//  Created by J.D. Healy on 3/3/15.
//  Copyright (c) 2015 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa
import ReactiveTask

//------------------------------------------------------------------------------
// MARK: - Command Line Interface
//------------------------------------------------------------------------------

/// Paths and launchers for Command Line Interfaces (CLIs) (mainly carthage’s).
internal enum CLI: String {
  case Carthage = "carthage"
  case Git = "git"

  private static let paths = [
    "carthage": carthagePath,
		"git": "/usr/bin/git"
  ]

	var path: String? {
    return CLI.paths[self.rawValue]
  }

	/// Launches a new shell task, using the associated path.
	///
	/// Returns a cold signal that will launch the task when started, then send
	/// aggregated data from `stdout` as String and complete upon success.
  func launch(
    #arguments: [String],
    workingDirectoryPath: String? = nil,
    environment: [String: String]? = nil,

		var modify modifiers: [Modifier] = [Modifier.Identity]
  ) -> ColdSignal<String> {

		let modified = reduce(modifiers,
			(
				launchPath: CLI.paths[self.rawValue]!,
				arguments: arguments,
				environment: environment,
				workingDirectoryPath: workingDirectoryPath
			)
		) { previous, value in
			return value.modify(
				launchPath: previous.launchPath,
				arguments: previous.arguments,
				environment: previous.environment,
				workingDirectoryPath: previous.workingDirectoryPath
			)
		}

    return launchTask(
      TaskDescription(
        launchPath: modified.launchPath,
        arguments: modified.arguments,
        workingDirectoryPath: modified.workingDirectoryPath,
        environment: modified.environment
      )
    ).tryMap(stringify)
  }

	func launch(
		#arguments: [String],
		workingDirectoryPath: Fixture,
		environment: [String: String]? = nil,

		var modify modifiers: [Modifier] = [Modifier.Identity]
  ) -> ColdSignal<String> {
		let temporaryDirectory = workingDirectoryPath.temporaryDirectory

		return launch(
			arguments: arguments,
			workingDirectoryPath: temporaryDirectory.path,
			environment: environment,
			modify: modifiers
		).on(completed: {
			_ = NSFileManager.defaultManager().trashItemAtURL(temporaryDirectory.URL, resultingItemURL: nil, error: nil)
		})

	}

	//------------------------------------------------------------------------------
	// MARK: - Modifier
	//------------------------------------------------------------------------------

	struct Modifier {

		let modify: (
			launchPath: String,
			arguments: [String],
			environment: [String: String]?,
			workingDirectoryPath: String?
		) -> (
			launchPath: String,
			arguments: [String],
			environment: [String: String]?,
			workingDirectoryPath: String?
		)

		static let Identity = Modifier(
			modify: { launchPath, arguments, environment, workingDirectoryPath in
				return (
					launchPath: launchPath,
					arguments: arguments,
					environment: environment,
					workingDirectoryPath: workingDirectoryPath
				)
			}
		)

		static func TTY(_ tty: Bool = true) -> Modifier {
			return Modifier(modify: { launchPath, arguments, environment, workingDirectoryPath in
				return (
					launchPath: bundle.pathForResource( (tty ? "tty" : "no-tty"), ofType: "zsh" )!,
					arguments: [ launchPath ] + arguments,
					environment: environment,
					workingDirectoryPath: workingDirectoryPath
				)
			})
		}

		static func ZSH(f: String -> String = { $0 }) -> Modifier {
			return Modifier(modify: { launchPath, arguments, environment, workingDirectoryPath in
				typealias Env = [String: String]

				let modifiedEnvironment = { (var environment: Env) -> Env in
					environment.updateValue("/var/empty", forKey: "ZDOTDIR")
					return environment
				}( environment ?? Env() )

				return (
					launchPath: bundle.pathForResource("zsh-argumentized", ofType: "zsh")!,
					arguments: [launchPath] + arguments,
					environment: modifiedEnvironment,
					workingDirectoryPath: workingDirectoryPath
				)
			})
		}

	}

}

//------------------------------------------------------------------------------
// MARK: - Resolve Carthage Path
//------------------------------------------------------------------------------

/// Path of `carthage` CLI executable. Located based off `CARTHAGE_PATH`
/// environment variable or `CarthageTests.xctest`. Fatally errors if the path
/// is not resolved, because without the path then tests can't test `carthage`.
private let carthagePath: String = ColdSignal.single( NSProcessInfo().environment["CARTHAGE_PATH"] as? NSString )
  .tryMap { $0.map(success) ?? Error.failure() }
  .tryMap { NSURL.fileURLWithPath($0, isDirectory: false).map(success) ?? Error.failure() }
  .catch { _ in
    // Search for the executable next to this bundle.
    return ColdSignal.single(bundle.bundleURL)
      .tryMap { $0.absoluteURL.map(success) ?? Error.failure() }
  }
	// Get containing directory of bundle.
	.tryMap { $0.URLByDeletingLastPathComponent?.path.map(success) ?? Error.failure() }
	// Search with `mdfind`
  .mergeMap {
    launchTask( TaskDescription( launchPath: "/usr/bin/mdfind", arguments: [
      "-onlyin", $0,
      "kMDItemFSName == 'carthage' && kMDItemContentType = 'public.unix-executable'"
    ] ) )
	}.tryMap(stringify)
  .tryMap { (output: String) -> Result<String> in
    // check for single path, followed by new line
    switch {
      (paths: $0, count: countElements($0))
    }(
      output.componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet()).filter { !$0.isEmpty }
    ) {
    case let (paths, count) where count == 1:
      if let first = paths.first {
        return success(first)
      } else { fallthrough }
    default:
      return Error.PathResolution.failure("Too many ‘carthage’s found.")
    }
  }.try { (path: String) -> Result<String> in
    // check for CarthageKit with `otool`.
    return launchTask( TaskDescription(launchPath: "/usr/bin/otool", arguments: [ "-L", path ]) )
			.tryMap(stringify)
      .try { (string: String) -> Result<()> in
        string.rangeOfString("CarthageKit.framework") != nil ?
          success() : Error.PathResolution.failure(
            "Command line interface ‘\(path)’ weirdly doesn't link against CarthageKit."
          )
      }.single()
  }.on(error: {
    fatalError($0.description)
  }).single().value()!
