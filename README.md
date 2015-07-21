![](Logo/PNG/header.png)

# Carthage [![GitHub license](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://raw.githubusercontent.com/Carthage/Carthage/master/LICENSE.md) [![GitHub release](https://img.shields.io/github/release/carthage/carthage.svg)](https://github.com/Carthage/Carthage/releases)

Carthage is intended to be the simplest way to add frameworks to your Cocoa application.

The basic [workflow](#adding-frameworks-to-an-application) looks something like this:

1. Create a [Cartfile][] that lists the frameworks you’d like to use in your project.
1. [Run Carthage](#adding-frameworks-to-an-application), which fetches and builds each framework you’ve listed.
1. Drag the built `.framework` binaries into your application’s Xcode project.

Carthage builds your dependencies and provides you with binary frameworks, but you retain full control over your project structure and setup. Carthage does not automatically modify your project files or your build settings.

## Differences between Carthage and CocoaPods

[CocoaPods](http://cocoapods.org/) is a long-standing dependency manager for Cocoa. So why was Carthage created?

Firstly, CocoaPods (by default) automatically creates and updates an Xcode workspace for your application and all dependencies. Carthage builds framework binaries using `xcodebuild`, but leaves the responsibility of integrating them up to the user. CocoaPods’ approach is easier to use, while Carthage’s is flexible and unintrusive.

The goal of CocoaPods is listed in its [README](https://github.com/CocoaPods/CocoaPods/blob/1703a3464674baecf54bd7e766f4b37ed8fc43f7/README.md) as follows:

> … to improve discoverability of, and engagement in, third party open-source libraries, by creating a more centralized ecosystem.

By contrast, Carthage has been created as a _decentralized_ dependency manager. There is no central list of projects, which reduces maintenance work and avoids any central point of failure. However, project discovery is more difficult—users must resort to GitHub’s [Trending](https://github.com/trending?l=swift) pages or similar.

CocoaPods projects must also have what’s known as a [podspec](http://guides.cocoapods.org/syntax/podspec.html) file, which includes metadata about the project and specifies how it should be built. Carthage uses `xcodebuild` to build dependencies, instead of integrating them into a single workspace, it doesn’t have a similar specification file but your dependencies must include their own Xcode project that describes how to build their products.

Ultimately, we created Carthage because we wanted the simplest tool possible—a dependency manager that gets the job done without taking over the responsibility of Xcode, and without creating extra work for framework authors. CocoaPods offers many amazing features that Carthage will never have, at the expense of additional complexity.

## Installing Carthage

To install the `carthage` tool on your system, please download and run the `Carthage.pkg` file for the latest  [release](https://github.com/Carthage/Carthage/releases), then follow the on-screen instructions.

Alternately, you can use [Homebrew](http://brew.sh) and install the `carthage` tool on your system simply by running `brew update` and `brew install carthage`.

If you’d like to run the latest development version (which may be highly unstable or incompatible), simply clone the `master` branch of the repository, then run `make install`.

## Adding frameworks to an application

Once you have Carthage [installed](#installing-carthage), you can begin adding frameworks to your project. Note that Carthage only supports dynamic frameworks, which are **only available on iOS 8 or later** (or any version of OS X).

### Getting started

##### If you're building for OS X

1. Create a [Cartfile][] that lists the frameworks you’d like to use in your project.
1. Run `carthage update`. This will fetch dependencies into a [Carthage/Checkouts][] folder, then build each one.
1. On your application targets’ “General” settings tab, in the “Embedded Binaries” section, drag and drop each framework you want to use from the [Carthage/Build][] folder on disk.

##### If you're building for iOS

1. Create a [Cartfile][] that lists the frameworks you’d like to use in your project.
1. Run `carthage update`. This will fetch dependencies into a [Carthage/Checkouts][] folder, then build each one.
1. On your application targets’ “General” settings tab, in the “Linked Frameworks and Libraries” section, drag and drop each framework you want to use from the [Carthage/Build][] folder on disk.
1. On your application targets’ “Build Phases” settings tab, click the “+” icon and choose “New Run Script Phase”. Create a Run Script with the following contents:

  ```sh
  /usr/local/bin/carthage copy-frameworks
  ```

  and add the paths to the frameworks you want to use under “Input Files”, e.g.:

  ```
  $(SRCROOT)/Carthage/Build/iOS/LlamaKit.framework
  $(SRCROOT)/Carthage/Build/iOS/ReactiveCocoa.framework
  ```

  This script works around an [App Store submission bug](http://www.openradar.me/radar?id=6409498411401216) triggered by universal binaries.

##### For both platforms

Along the way, Carthage will have created some [build artifacts][Artifacts]. The most important of these is the [Cartfile.resolved][] file, which lists the versions that were actually built for each framework. **Make sure to commit your [Cartfile.resolved][]**, because anyone else using the project will need that file to build the same framework versions.

After you’ve finished the above steps and pushed your changes, other users of the project only need to fetch the repository and run `carthage bootstrap` to get started with the frameworks you’ve added.

### Adding frameworks to unit tests or a framework

Using Carthage for the dependencies of any arbitrary target is fairly similar to [using Carthage for an application](#adding-frameworks-to-an-application). The main difference lies in how the frameworks are actually set up and linked in Xcode.

Because non-application targets are missing the “Embedded Binaries” section in their build settings, you must instead drag the [built frameworks][Carthage/Build] to the “Link Binaries With Libraries” build phase.

In rare cases, you may want to also copy each dependency into the build product (e.g., to embed dependencies within the outer framework, or make sure dependencies are present in a test bundle). To do this, create a new “Copy Files” build phase with the “Frameworks” destination, then add the framework reference there as well.

### Upgrading frameworks

If you’ve modified your [Cartfile][], or you want to update to the newest versions of each framework (subject to the requirements you’ve specified), simply run the `carthage update` command again.

### Nested dependencies

If the framework you want to add to your project has dependencies explicitly listed in a [Cartfile][], Carthage will automatically retrieve them for you. You will then have to **drag them yourself into your project** from the [Carthage/Build] folder.

### Using submodules for dependencies

By default, Carthage will directly [check out][Carthage/Checkouts] dependencies’ source files into your project folder, leaving you to commit or ignore them as you choose. If you’d like to have dependencies available as Git submodules instead (perhaps so you can commit and push changes within them), you can run `carthage update` or `carthage checkout` with the `--use-submodules` flag.

When run this way, Carthage will write to your repository’s `.gitmodules` and `.git/config` files, and automatically update the submodules when the dependencies’ versions change.

### Automatically rebuilding dependencies

If you want to work on your dependencies during development, and want them to be automatically rebuilt when you build your parent project, you can add a Run Script build phase that invokes Carthage like so:

```sh
/usr/local/bin/carthage build --platform "$PLATFORM_NAME" "$SRCROOT"
```

Note that you should be [using submodules](#using-submodules-for-dependencies) before doing this, because plain checkouts [should not be modified][Carthage/Checkouts] directly.

## Supporting Carthage for your framework

**Carthage only officially supports dynamic frameworks**. Dynamic frameworks can be used on any version of OS X, but only on **iOS 8 or later**.

Because Carthage has no centralized package list, and no project specification format, **most frameworks should build automatically**.

The specific requirements of any framework project are listed below.

### Share your Xcode schemes

Carthage will only build Xcode schemes that are shared from your `.xcodeproj`. You can see if all of your intended schemes build successfully by running `carthage build --no-skip-current`, then checking the [Carthage/Build][] folder.

If an important scheme is not built when you run that command, open Xcode and make sure that the [scheme is marked as “Shared,”](https://developer.apple.com/library/ios/recipes/xcode_help-scheme_editor/Articles/SchemeShare.html) so Carthage can discover it.


### Resolve build failures

If you encounter build failures in `carthage build --no-skip-current`, try running `xcodebuild -scheme SCHEME -workspace WORKSPACE build` or `xcodebuild -scheme SCHEME -project PROJECT build` (with the actual values) and see if the same failure occurs there. This should hopefully yield enough information to resolve the problem.

If you have multiple versions of the Apple developer tools installed (an Xcode beta, for example), use `xcode-select` to change which version Carthage uses.

If you’re still not able to build your framework with Carthage, please [open an issue](https://github.com/Carthage/Carthage/issues/new) and we’d be happy to help!

### Tag stable releases

Carthage determines which versions of your framework are available by searching through the tags published on the repository, and trying to interpret each tag name as a [semantic version](http://semver.org/). For example, in the tag `v1.2`, the semantic version is 1.2.0.

Tags without any version number, or with any characters following the version number (e.g., `1.2-alpha-1`) are currently unsupported, and will be ignored.

### Archive prebuilt frameworks into one zip file

Carthage can automatically use prebuilt frameworks, instead of building from scratch, if they are attached to a [GitHub Release](https://help.github.com/articles/about-releases/) on your project’s repository.

To offer prebuilt frameworks for a specific tag, the binaries for _all_ supported platforms should be zipped up together into _one_ archive, and that archive should be attached to a published Release corresponding to that tag. The attachment should include `.framework` in its name (e.g., `ReactiveCocoa.framework.zip`), to indicate to Carthage that it contains binaries.

Prerelease or draft Releases will be automatically ignored, even if they correspond to the desired tag.

### Declare your compatibility

Want to advertise that your project can be used with Carthage? You can add a compatibility badge:

[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)

… to your README, by simply inserting the following Markdown:

```markdown
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
```

## CarthageKit

Most of the functionality of the `carthage` command line tool is actually encapsulated in a framework named CarthageKit.

If you’re interested in using Carthage as part of another tool, or perhaps extending the functionality of Carthage, take a look at the [CarthageKit][] source code to see if the API fits your needs.

## License

Carthage is released under the [MIT License](LICENSE.md).

Header backdrop photo is released under the [CC BY-NC-SA 2.0](https://creativecommons.org/licenses/by-nc-sa/2.0/) license. Original photo by [Richard Mortel](https://www.flickr.com/photos/prof_richard/).

[Artifacts]: Documentation/Artifacts.md
[Cartfile]: Documentation/Artifacts.md#cartfile
[Cartfile.resolved]: Documentation/Artifacts.md#cartfileresolved
[Carthage/Build]: Documentation/Artifacts.md#carthagebuild
[Carthage/Checkouts]: Documentation/Artifacts.md#carthagecheckouts
[CarthageKit]: Source/CarthageKit
