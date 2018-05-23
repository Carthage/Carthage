![](Logo/PNG/header.png)

# Carthage [![GitHub license](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://raw.githubusercontent.com/Carthage/Carthage/master/LICENSE.md) [![GitHub release](https://img.shields.io/github/release/carthage/carthage.svg)](https://github.com/Carthage/Carthage/releases)

Carthage is intended to be the simplest way to add frameworks to your Cocoa application.

Carthage builds your dependencies and provides you with binary frameworks, but you retain full control over your project structure and setup. Carthage does not automatically modify your project files or your build settings.

- [Quick Start](#quick-start)
- [Installing Carthage](#installing-carthage)
- [Adding frameworks to an application](#adding-frameworks-to-an-application)
	- [Getting started](#getting-started)
		- [If you're building for OS X](#if-youre-building-for-os-x)
		- [If you're building for iOS, tvOS, or watchOS](#if-youre-building-for-ios-tvos-or-watchos)
		- [For both platforms](#for-both-platforms)
		- [(Optionally) Add build phase to warn about outdated dependencies](#optionally-add-build-phase-to-warn-about-outdated-dependencies)
		- [Swift binary framework download compatibility](#swift-binary-framework-download-compatibility)
	- [Running a project that uses Carthage](#running-a-project-that-uses-carthage)
	- [Adding frameworks to unit tests or a framework](#adding-frameworks-to-unit-tests-or-a-framework)
	- [Upgrading frameworks](#upgrading-frameworks)
		- [Experimental Resolver](#experimental-resolver)
	- [Nested dependencies](#nested-dependencies)
	- [Using submodules for dependencies](#using-submodules-for-dependencies)
	- [Automatically rebuilding dependencies](#automatically-rebuilding-dependencies)
	- [Caching builds](#caching-builds)
	- [Bash/Zsh/Fish completion](#bashzshfish-completion)
- [Supporting Carthage for your framework](#supporting-carthage-for-your-framework)
	- [Share your Xcode schemes](#share-your-xcode-schemes)
	- [Resolve build failures](#resolve-build-failures)
	- [Tag stable releases](#tag-stable-releases)
	- [Archive prebuilt frameworks into one zip file](#archive-prebuilt-frameworks-into-one-zip-file)
		- [Use travis-ci to upload your tagged prebuilt frameworks](#use-travis-ci-to-upload-your-tagged-prebuilt-frameworks)
	- [Build static frameworks to speed up your app’s launch times](#build-static-frameworks-to-speed-up-your-apps-launch-times)
	- [Declare your compatibility](#declare-your-compatibility)
- [Known issues](#known-issues)
	- [DWARFs symbol problem](#dwarfs-symbol-problem)
- [CarthageKit](#carthagekit)
- [Differences between Carthage and CocoaPods](#differences-between-carthage-and-cocoapods)
- [License](#license)

## Quick Start

1. Get Carthage by running `brew install carthage` or choose [another installation method](#installing-carthage)
1. Create a [Cartfile][] in the same directory where your `.xcodeproj` or `.xcworkspace` is
1. List the desired dependencies in the [Cartfile][], for example:

	```
	github "Alamofire/Alamofire" ~> 4.7.2
	```
	
1. Run `carthage update`
1. A `Cartfile.resolved` file and a `Carthage` directory will appear in the same directory where your `.xcodeproj` or `.xcworkspace` is
1. Drag the built `.framework` binaries from `Carthage/Build/<platform>` into your application’s Xcode project.
1. If you are using Carthage for an application, follow the remaining steps, otherwise stop here.
1. On your application targets’ _Build Phases_ settings tab, click the _+_ icon and choose _New Run Script Phase_. Create a Run Script in which you specify your shell (ex: `/bin/sh`), add the following contents to the script area below the shell:

    ```sh
    /usr/local/bin/carthage copy-frameworks
    ```

1. Add the paths to the frameworks you want to use under “Input Files". For example:

    ```
    $(SRCROOT)/Carthage/Build/iOS/Alamofire.framework
    ```

1. Add the paths to the copied frameworks to the “Output Files”. For example:

    ```
    $(BUILT_PRODUCTS_DIR)/$(FRAMEWORKS_FOLDER_PATH)/Alamofire.framework
    ```

For an in depth guide, read on from [Adding frameworks to an application](#adding-frameworks-to-an-application)

## Installing Carthage

There are multiple options for installing Carthage:

* **Installer:** Download and run the `Carthage.pkg` file for the latest [release](https://github.com/Carthage/Carthage/releases), then follow the on-screen instructions. If you are installing the pkg via CLI, you might need to run `sudo chown -R $(whoami) /usr/local` first.

* **Homebrew:** You can use [Homebrew](http://brew.sh) and install the `carthage` tool on your system simply by running `brew update` and `brew install carthage`. (note: if you previously installed the binary version of Carthage, you should delete `/Library/Frameworks/CarthageKit.framework`).

* **From source:** If you’d like to run the latest development version (which may be highly unstable or incompatible), simply clone the `master` branch of the repository, then run `make install`. Requires Xcode 9.0 (Swift 4.0).

## Adding frameworks to an application

Once you have Carthage [installed](#installing-carthage), you can begin adding frameworks to your project. Note that Carthage only supports dynamic frameworks, which are **only available on iOS 8 or later** (or any version of OS X).

### Getting started

##### If you're building for OS X

1. Create a [Cartfile][] that lists the frameworks you’d like to use in your project.
1. Run `carthage update`. This will fetch dependencies into a [Carthage/Checkouts][] folder and build each one or download a pre-compiled framework.
1. On your application targets’ _General_ settings tab, in the _Embedded Binaries_ section, drag and drop each framework you want to use from the [Carthage/Build][] folder on disk.

Additionally, you'll need to copy debug symbols for debugging and crash reporting on OS X.

1. On your application target’s _Build Phases_ settings tab, click the _+_ icon and choose _New Copy Files Phase_.
1. Click the _Destination_ drop-down menu and select _Products Directory_.
1. For each framework you’re using, drag and drop its corresponding dSYM file.

##### If you're building for iOS, tvOS, or watchOS

1. Create a [Cartfile][] that lists the frameworks you’d like to use in your project.
1. Run `carthage update`. This will fetch dependencies into a [Carthage/Checkouts][] folder, then build each one or download a pre-compiled framework.
1. On your application targets’ _General_ settings tab, in the “Linked Frameworks and Libraries” section, drag and drop each framework you want to use from the [Carthage/Build][] folder on disk.
1. On your application targets’ _Build Phases_ settings tab, click the _+_ icon and choose _New Run Script Phase_. Create a Run Script in which you specify your shell (ex: `/bin/sh`), add the following contents to the script area below the shell:

    ```sh
    /usr/local/bin/carthage copy-frameworks
    ```

1. Add the paths to the frameworks you want to use under “Input Files". For example:

    ```
    $(SRCROOT)/Carthage/Build/iOS/Result.framework
    $(SRCROOT)/Carthage/Build/iOS/ReactiveSwift.framework
    $(SRCROOT)/Carthage/Build/iOS/ReactiveCocoa.framework
    ```

1. Add the paths to the copied frameworks to the “Output Files”. For example:

    ```
    $(BUILT_PRODUCTS_DIR)/$(FRAMEWORKS_FOLDER_PATH)/Result.framework
    $(BUILT_PRODUCTS_DIR)/$(FRAMEWORKS_FOLDER_PATH)/ReactiveSwift.framework
    $(BUILT_PRODUCTS_DIR)/$(FRAMEWORKS_FOLDER_PATH)/ReactiveCocoa.framework
    ```

    With output files specified alongside the input files, Xcode only needs to run the script when the input files have changed or the output files are missing. This means dirty builds will be faster when you haven't rebuilt frameworks with Carthage.

This script works around an [App Store submission bug](http://www.openradar.me/radar?id=6409498411401216) triggered by universal binaries and ensures that necessary bitcode-related files and dSYMs are copied when archiving.

With the debug information copied into the built products directory, Xcode will be able to symbolicate the stack trace whenever you stop at a breakpoint. This will also enable you to step through third-party code in the debugger.

When archiving your application for submission to the App Store or TestFlight, Xcode will also copy these files into the dSYMs subdirectory of your application’s `.xcarchive` bundle.

##### For both platforms

Along the way, Carthage will have created some [build artifacts][Artifacts]. The most important of these is the [Cartfile.resolved][] file, which lists the versions that were actually built for each framework. **Make sure to commit your [Cartfile.resolved][]**, because anyone else using the project will need that file to build the same framework versions.

##### (Optionally) Add build phase to warn about outdated dependencies

You can add a Run Script phase to automatically warn you when one of your dependencies is out of date.

1. On your application targets’ `Build Phases` settings tab, click the `+` icon and choose `New Run Script Phase`. Create a Run Script in which you specify your shell (ex: `/bin/sh`), add the following contents to the script area below the shell:

```sh
/usr/local/bin/carthage outdated --xcode-warnings
```

##### Swift binary framework download compatibility

Carthage will check to make sure that downloaded Swift (and mixed Objective-C/Swift) frameworks were built with the same version of Swift that is in use locally. If there is a version mismatch, Carthage will proceed to build the framework from source. If the framework cannot be built from source, Carthage will fail.

Because Carthage uses the output of `xcrun swift --version` to determine the local Swift version, make sure to run Carthage commands with the Swift toolchain that you intend to use. For many use cases, nothing additional is needed. However, for example, if you are building a Swift 2.3 project using Xcode 8.x, one approach to specifying your default `swift` for `carthage bootstrap` is to use the following command:

```
TOOLCHAINS=com.apple.dt.toolchain.Swift_2_3 carthage bootstrap
```

### Running a project that uses Carthage

After you’ve finished the above steps and pushed your changes, other users of the project only need to fetch the repository and run `carthage bootstrap` to get started with the frameworks you’ve added.

### Adding frameworks to unit tests or a framework

Using Carthage for the dependencies of any arbitrary target is fairly similar to [using Carthage for an application](#adding-frameworks-to-an-application). The main difference lies in how the frameworks are actually set up and linked in Xcode.

Because unit test targets are missing the _Linked Frameworks and Libraries_ section in their _General_ settings tab, you must instead drag the [built frameworks][Carthage/Build] to the _Link Binaries With Libraries_ build phase.

In the Test target under the _Build Settings_ tab, add `@loader_path/Frameworks` to the _Runpath Search Paths_ if it isn't already present.

In rare cases, you may want to also copy each dependency into the build product (e.g., to embed dependencies within the outer framework, or make sure dependencies are present in a test bundle). To do this, create a new _Copy Files_ build phase with the _Frameworks_ destination, then add the framework reference there as well.

### Upgrading frameworks

If you’ve modified your [Cartfile][], or you want to update to the newest versions of each framework (subject to the requirements you’ve specified), simply run the `carthage update` command again.

If you only want to update one, or specific, dependencies, pass them as a space-separated list to the `update` command. e.g.

```
carthage update Box
```

or

```
carthage update Box Result
```

##### Experimental Resolver

A rewrite of the logic for upgrading frameworks was done with the aim of increasing speed and reducing memory usage. It is currently an opt-in feature. It can be used by passing `--new-resolver` to the update command, e.g.,

```
carthage update --new-resolver Box
```

If you are experiencing performance problems during updates, please give the new resolver a try


### Nested dependencies

If the framework you want to add to your project has dependencies explicitly listed in a [Cartfile][], Carthage will automatically retrieve them for you. You will then have to **drag them yourself into your project** from the [Carthage/Build] folder.

If the embedded framework in your project has dependencies to other frameworks you must  **link them to application target** (even if application target does not have dependency to that frameworks and never uses them).

### Using submodules for dependencies

By default, Carthage will directly [check out][Carthage/Checkouts] dependencies’ source files into your project folder, leaving you to commit or ignore them as you choose. If you’d like to have dependencies available as Git submodules instead (perhaps so you can commit and push changes within them), you can run `carthage update` or `carthage checkout` with the `--use-submodules` flag.

When run this way, Carthage will write to your repository’s `.gitmodules` and `.git/config` files, and automatically update the submodules when the dependencies’ versions change.

### Automatically rebuilding dependencies

If you want to work on your dependencies during development, and want them to be automatically rebuilt when you build your parent project, you can add a Run Script build phase that invokes Carthage like so:

```sh
/usr/local/bin/carthage build --platform "$PLATFORM_NAME" --project-directory "$SRCROOT"
```

Note that you should be [using submodules](#using-submodules-for-dependencies) before doing this, because plain checkouts [should not be modified][Carthage/Checkouts] directly.

### Caching builds

By default Carthage will rebuild a dependency regardless of whether it's the same resolved version as before. Passing the `--cache-builds` will cause carthage to avoid rebuilding a dependency if it can. See information on [version files][VersionFile] for details on how Carthage performs this caching.

Note: At this time `--cache-builds` is incompatible with `--use-submodules`. Using both will result in working copy and committed changes to your submodule dependency not being correctly rebuilt. See [#1785](https://github.com/Carthage/Carthage/issues/1785) for details.

### Bash/Zsh/Fish completion

Auto completion of Carthage commands and options are available as documented in [Bash/Zsh/Fish Completion][Bash/Zsh/Fish Completion].

## Supporting Carthage for your framework

**Carthage only officially supports dynamic frameworks**. Dynamic frameworks can be used on any version of OS X, but only on **iOS 8 or later**.

Because Carthage has no centralized package list, and no project specification format, **most frameworks should build automatically**.

The specific requirements of any framework project are listed below.

### Share your Xcode schemes

Carthage will only build Xcode schemes that are shared from your `.xcodeproj`. You can see if all of your intended schemes build successfully by running `carthage build --no-skip-current`, then checking the [Carthage/Build][] folder.

If an important scheme is not built when you run that command, open Xcode and make sure that the [scheme is marked as _Shared_](https://developer.apple.com/library/content/documentation/IDEs/Conceptual/xcode_guide-continuous_integration/ConfigureBots.html#//apple_ref/doc/uid/TP40013292-CH9-SW3), so Carthage can discover it.


### Resolve build failures

If you encounter build failures in `carthage build --no-skip-current`, try running `xcodebuild -scheme SCHEME -workspace WORKSPACE build` or `xcodebuild -scheme SCHEME -project PROJECT build` (with the actual values) and see if the same failure occurs there. This should hopefully yield enough information to resolve the problem.

If you have multiple versions of the Apple developer tools installed (an Xcode beta, for example), use `xcode-select` to change which version Carthage uses.

If you’re still not able to build your framework with Carthage, please [open an issue](https://github.com/Carthage/Carthage/issues/new) and we’d be happy to help!

### Tag stable releases

Carthage determines which versions of your framework are available by searching through the tags published on the repository, and trying to interpret each tag name as a [semantic version](https://semver.org/). For example, in the tag `v1.2`, the semantic version is 1.2.0.

Tags without any version number, or with any characters following the version number (e.g., `1.2-alpha-1`) are currently unsupported, and will be ignored.

### Archive prebuilt frameworks into one zip file

Carthage can automatically use prebuilt frameworks, instead of building from scratch, if they are attached to a [GitHub Release](https://help.github.com/articles/about-releases/) on your project’s repository or via a binary project definition file.

To offer prebuilt frameworks for a specific tag, the binaries for _all_ supported platforms should be zipped up together into _one_ archive, and that archive should be attached to a published Release corresponding to that tag. The attachment should include `.framework` in its name (e.g., `ReactiveCocoa.framework.zip`), to indicate to Carthage that it contains binaries.

You can perform the archiving operation above with the `carthage archive` command as follows:

```sh
carthage build --no-skip-current
carthage archive YourFrameworkName
```

Draft Releases will be automatically ignored, even if they correspond to the desired tag.

#### Use travis-ci to upload your tagged prebuilt frameworks

It is possible to use travis-ci in order to build and upload your tagged releases.

1. [Install travis CLI](https://github.com/travis-ci/travis.rb#installation) with `gem install travis`
1. [Setup](https://docs.travis-ci.com/user/getting-started/) travis-ci for your repository (Steps 1 and 2)
1. Create `.travis.yml` file at the root of your repository based on that template. Set `FRAMEWORK_NAME` to the correct value.

	Replace PROJECT_PLACEHOLDER and SCHEME_PLACEHOLDER

	If you are using a *workspace* instead of a *project* remove the xcode_project line and uncomment the xcode_workspace line.

	The project should be in the format: MyProject.xcodeproj

	The workspace should be in the format: MyWorkspace.xcworkspace

	Feel free to update the `xcode_sdk` value to another SDK, note that testing on iphoneos SDK would require you to upload a code signing identity

	For more informations you can visit [travis docs for objective-c projects](https://docs.travis-ci.com/user/languages/objective-c)

	```YAML
	language: objective-c
	osx_image: xcode7.3
	xcode_project: <PROJECT_PLACEHOLDER>
	# xcode_workspace: <WORKSPACE_PLACEHOLDER>
	xcode_scheme: <SCHEME_PLACEHOLDER>
	xcode_sdk: iphonesimulator9.3
	env:
	  global:
	    - FRAMEWORK_NAME=<THIS_IS_A_PLACEHOLDER_REPLACE_ME>
	before_install:
	  - brew update
	  - brew outdated carthage || brew upgrade carthage
	before_script:
	  # bootstrap the dependencies for the project
	  # you can remove if you don't have dependencies
	  - carthage bootstrap
	before_deploy:
	  - carthage build --no-skip-current
	  - carthage archive $FRAMEWORK_NAME
	```
1. Run `travis setup releases`, follow documentation [here](https://docs.travis-ci.com/user/deployment/releases/)

	This command will encode your GitHub credentials into the `.travis.yml` file in order to let travis upload the release to GitHub.com
	When prompted for the file to upload, enter `$FRAMEWORK_NAME.framework.zip`

1. Update the deploy section to run on tags:

	In `.travis.yml` locate:

	```YAML
	on:
	  repo: repo/repo
	```

	And add `tags: true` and `skip_cleanup: true`:

	```YAML
	skip_cleanup: true
	on:
	  repo: repo/repo
	  tags: true
	```

	That will let travis know to create a deployment when a new tag is pushed and prevent travis to cleanup the generated zip file

### Build static frameworks to speed up your app’s launch times

If you embed many dynamic frameworks into your app, its pre-main launch times may be quite slow. Carthage is able to help mitigate this by building your dynamic frameworks as static frameworks instead. Static frameworks can be linked directly into your application or merged together into a larger dynamic framework with a few simple modifications to your workflow, which can result in dramatic reductions in pre-main lauch times. See the [StaticFrameworks][StaticFrameworks] doc for details.

*Please note that a few caveats apply to this approach:*
- Swift static frameworks are not officially supported by Apple
- This is an advanced workflow that is not built into Carthage, YMMV

### Declare your compatibility

Want to advertise that your project can be used with Carthage? You can add a compatibility badge:

[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)

… to your `README`, by simply inserting the following Markdown:

```markdown
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
```
## Known issues

##### DWARFs symbol problem
Pre-built framework cannot be debugged using step execution on other machine than on which the framework was built. Simply `carthage bootstrap/build/update --no-use-binaries` should fix this, but for more automated workaround, see [#924](https://github.com/Carthage/Carthage/issues/924). Dupe [rdar://23551273](http://www.openradar.me/23551273) if you want Apple to fix the root cause of this problem.

## CarthageKit

Most of the functionality of the `carthage` command line tool is actually encapsulated in a framework named CarthageKit.

If you’re interested in using Carthage as part of another tool, or perhaps extending the functionality of Carthage, take a look at the [CarthageKit][] source code to see if the API fits your needs.

## Differences between Carthage and CocoaPods

[CocoaPods](http://cocoapods.org/) is a long-standing dependency manager for Cocoa. So why was Carthage created?

Firstly, CocoaPods (by default) automatically creates and updates an Xcode workspace for your application and all dependencies. Carthage builds framework binaries using `xcodebuild`, but leaves the responsibility of integrating them up to the user. CocoaPods’ approach is easier to use, while Carthage’s is flexible and unintrusive.

The goal of CocoaPods is listed in its [README](https://github.com/CocoaPods/CocoaPods/blob/1703a3464674baecf54bd7e766f4b37ed8fc43f7/README.md) as follows:

> … to improve discoverability of, and engagement in, third party open-source libraries, by creating a more centralized ecosystem.

By contrast, Carthage has been created as a _decentralized_ dependency manager. There is no central list of projects, which reduces maintenance work and avoids any central point of failure. However, project discovery is more difficult—users must resort to GitHub’s [Trending](https://github.com/trending?l=swift) pages or similar.

CocoaPods projects must also have what’s known as a [podspec](http://guides.cocoapods.org/syntax/podspec.html) file, which includes metadata about the project and specifies how it should be built. Carthage uses `xcodebuild` to build dependencies, instead of integrating them into a single workspace, it doesn’t have a similar specification file but your dependencies must include their own Xcode project that describes how to build their products.

Ultimately, we created Carthage because we wanted the simplest tool possible—a dependency manager that gets the job done without taking over the responsibility of Xcode, and without creating extra work for framework authors. CocoaPods offers many amazing features that Carthage will never have, at the expense of additional complexity.

## License

Carthage is released under the [MIT License](LICENSE.md).

Header backdrop photo is released under the [CC BY-NC-SA 2.0](https://creativecommons.org/licenses/by-nc-sa/2.0/) license. Original photo by [Richard Mortel](https://www.flickr.com/photos/prof_richard/).

[Artifacts]: Documentation/Artifacts.md
[Cartfile]: Documentation/Artifacts.md#cartfile
[Cartfile.resolved]: Documentation/Artifacts.md#cartfileresolved
[Carthage/Build]: Documentation/Artifacts.md#carthagebuild
[Carthage/Checkouts]: Documentation/Artifacts.md#carthagecheckouts
[Bash/Zsh/Fish Completion]: Documentation/BashZshFishCompletion.md
[CarthageKit]: Source/CarthageKit
[VersionFile]: Documentation/VersionFile.md
[StaticFrameworks]: Documentation/StaticFrameworks.md

