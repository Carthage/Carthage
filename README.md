# Carthage

A simple dependency manager for Cocoa.

The goal of Carthage is straightforward: to resolve complex dependency graphs in the simplest way possible, without supplanting or duplicating the existing Cocoa toolchain. Carthage uses the normal Xcode tooling for building and linking, and at no point will it modify your project files or overwrite your build settings.

### Installation

To install the `carthage` tool on your system, simply clone the repository and run `sudo make install`.

### Usage

Once you have Carthage [installed](#installation), create a [Cartfile](Documentation/Cartfile.md) that lists the dependencies of your project.

Then, to actually set up those dependencies:

1. Run `carthage bootstrap`. This will clone and build all dependencies recursively.
1. Commit the `Cartfile.lock` file created by Carthage. This “pins” your dependencies, so other checkouts of your repository will use the same versions for consistency.
1. Drag the `.framework` bundles for your dependencies into your Xcode project, and add them to all targets that depend upon them.
1. In your targets’ “General” settings, add each framework to the “Embedded Binaries” section.

Whenever you modify your `Cartfile` in the future, or whenever you want to update to newer dependencies (subject to the version restrictions listed in the `Cartfile`), you can run the `carthage update` command. For any dependencies added or removed in this way, make sure to update your project file accordingly.

### License

Carthage is released under the [MIT License](LICENSE.md).
