# Carthage

A simple package manager for Cocoa.

The goal of Carthage is straightforward: to resolve complex dependency graphs in the simplest way possible, without supplanting or duplicating the existing Cocoa toolchain.

### Process

The package management process looks like this:

1. Your project specifies its dependencies, and which versions it will accept
1. Those dependencies specify their own dependencies in the same way
1. Carthage picks one version of each dependency (no matter how nested), and builds a framework from it
1. All of the frameworks are linked together at the application level

All along the way, Carthage will use the normal Xcode tooling for building and linking. At no point will it modify your project files or overwrite your build settings.

### License

Carthage is released under the [MIT License](LICENSE.md).
