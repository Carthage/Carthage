# Carthage

Carthage is intended to be the simplest way to add frameworks to your Cocoa application.

The basic [workflow](#adding-frameworks-to-an-application) looks something like this:

1. Create a [Cartfile][] that lists the frameworks you’d like to use in your project.
1. [Run Carthage](#adding-frameworks-to-an-application), which fetches and builds each framework you’ve listed.
1. Drag the built `.framework` binaries into your application’s Xcode project.

Carthage builds your dependencies and provides you with binary frameworks, but you retain full control over your project structure and setup. Carthage does not automatically modify your project files or your build settings.

## Differences between Carthage and CocoaPods

[CocoaPods](http://cocoapods.org/) is a long-standing dependency manager for Cocoa, the goal for which is described in its [README](https://github.com/CocoaPods/CocoaPods/blob/1703a3464674baecf54bd7e766f4b37ed8fc43f7/README.md) as follows:

> … to improve discoverability of, and engagement in, third party open-source libraries, by creating a more centralized ecosystem.

By contrast, Carthage has been created as a _decentralized_ dependency manager. There is no central list of projects, which reduces maintenance work and avoids any central point of failure. However, project discovery is more difficult—users must resort to GitHub’s [Trending](https://github.com/trending?l=swift) pages or similar.

CocoaPods automatically creates and updates an Xcode workspace for your application and all dependencies. Carthage builds framework binaries, but leaves the responsibility of integrating them up to the user. CocoaPods’ approach is easier to use, while Carthage’s is flexible and unintrusive.

CocoaPods projects must also have what’s known as a [podspec](http://guides.cocoapods.org/syntax/podspec.html) file, which includes metadata about the project and specifies how it should be built. Because Carthage uses `xcodebuild` to build dependencies, instead of integrating them into a single workspace, it doesn’t have a similar specification file.

Ultimately, we created Carthage because we wanted the simplest tool possible—a dependency manager that gets the job done without taking over the responsibility of Xcode, and without creating extra work for framework authors. CocoaPods offers many amazing features that Carthage will never have, at the expense of additional complexity.

Whichever tool you choose to use on your project, we’re happy to have offered the choice!

## Installing Carthage

To install the `carthage` tool on your system, please download and run the `Carthage.pkg` file for the latest  [release](https://github.com/Carthage/Carthage/releases), then follow the on-screen instructions.

If you’d like to run the latest development version (which may be highly unstable or incompatible), simply clone the `master` branch of the repository, run `make package`, then open the created `Carthage.pkg` to begin the installation process.

## Adding frameworks to an application

Once you have Carthage [installed](#installing-carthage), you can begin adding frameworks to your project:

1. Create a [Cartfile][] that lists the frameworks you’d like to use in your project.
1. Run `carthage update`. This will fetch dependencies into a [Carthage.checkout][] folder, then build each one.
1. On your application targets’ “General” settings tab, in the “Embedded Binaries” section, drag and drop each framework you want to use from the [Carthage.build][] folder on disk.

Along the way, Carthage will have created some [build artifacts][Artifacts]. The most important of these is the [Cartfile.lock][] file, which lists the versions that were actually built for each framework. **Make sure to commit your [Cartfile.lock][]**, because anyone else using the project will need that file to build the same framework versions.

After you’ve finished the above steps and pushed your changes, other users of the project only need to fetch the repository and run `carthage bootstrap` to get started with the frameworks you’ve added.

### Adding frameworks to unit tests or a framework

Using Carthage for the dependencies of any arbitrary target is fairly similar to [using Carthage for an application](#adding-frameworks-to-an-application). The main difference lies in how the frameworks are actually set up and linked in Xcode.

Because non-application targets are missing the “Embedded Binaries” section in their build settings, you must instead drag the [built frameworks][Carthage.build] to the “Link Binaries With Libraries” build phase.

In rare cases, you may want to also copy each dependency into the build product (e.g., to embed dependencies within the outer framework, or make sure dependencies are present in a test bundle). To do this, create a new “Copy Files” build phase with the “Frameworks” destination, then add the framework reference there as well.

### Upgrading frameworks

If you’ve modified your [Cartfile][], or you want to update to the newest versions of each framework (subject to the requirements you’ve specified), simply run the `carthage update` command again.

## Supporting Carthage for your framework

Because Carthage has no centralized package list, and no project specification format, **most frameworks should build automatically**.

If you are a framework developer, and would like Carthage to be able to build your framework, first see if all your schemes build successfully by running `carthage build --no-skip-current`, then checking the [Carthage.build][] folder.

If an important scheme is not built when you run that command, open Xcode and make sure that the scheme is marked as “Shared,” so Carthage can discover it.

If you encounter build failures, try running `xcodebuild -scheme SCHEME -workspace WORKSPACE build` or `xcodebuild -scheme SCHEME -project PROJECT build` (with the actual values) and see if the same failure occurs there. This should hopefully yield enough information to resolve the problem.

If, after all of the above, you’re still not able to build your framework with Carthage, please [open an issue](https://github.com/Carthage/Carthage/issues/new) and we’d be happy to help!

## CarthageKit

Most of the functionality of the `carthage` command line tool is actually encapsulated in a framework named CarthageKit.

If you’re interested in using Carthage as part of another tool, or perhaps extending the functionality of Carthage, take a look at the [CarthageKit][] source code to see if the API fits your needs.

## License

Carthage is released under the [MIT License](LICENSE.md).

[Artifacts]: Documentation/Artifacts.md
[Cartfile]: Documentation/Artifacts.md#cartfile
[Cartfile.lock]: Documentation/Artifacts.md#cartfilelock
[Carthage.build]: Documentation/Artifacts.md#carthagebuild
[Carthage.checkout]: Documentation/Artifacts.md#carthagecheckout
[CarthageKit]: CarthageKit
