# Artifacts

This document lists all files and folders used or created by Carthage, and the purpose of each.

## Cartfile

A `Cartfile` describes your project’s dependencies to Carthage, allowing it to resolve and build them for you.

Dependency specifications consist of two main parts: the [origin](#origin), and the [version requirement](#version-requirement).

#### Origin

The only supported origins right now are GitHub.com repositories, specified with the `github` keyword:

```
github "ReactiveCocoa/ReactiveCocoa"
```

… or other Git repositories, specified with the `git` keyword:

```
git "https://enterprise.local/desktop/git-error-translations.git"
```

Other possible origins may be added in the future. If there’s something specific you’d like to see, please [file an issue](https://github.com/Carthage/Carthage/issues/new).

#### Version requirement

Carthage supports three kinds of version requirements:

1. `>= 1.0` for “at least version 1.0”
1. `~> 1.0` for “compatible with version 1.0”
1. `== 1.0` for “exactly version 1.0”

If no version requirement is given, any version of the dependency is allowed.

Compatibility is determined according to [Semantic Versioning](http://semver.org/). This means that any version greater than or equal to 1.5.1, but less than 2.0, will be considered “compatible” with 1.5.1.

#### Example Cartfile

```
# Require version 2.3.1 or later
github "ReactiveCocoa/ReactiveCocoa" >= 2.3.1

# Require version 1.x
github "Mantle/Mantle" ~> 1.0    # (1.0 or later, but less than 2.0)

# Require exactly version 0.4.1
github "jspahrsummers/libextobjc" == 0.4.1

# Use the latest version
github "jspahrsummers/xcconfigs"

# Use a project from GitHub Enterprise, or any arbitrary server
git "https://enterprise.local/desktop/git-error-translations.git" >= 0.1
```

## Cartfile.lock

After running the `carthage update` command, a file named `Cartfile.lock` will be created alongside the `Cartfile` in the working directory. This file specifies precisely _which_ versions were chosen of each dependency, and lists all dependencies (even nested ones).

The `Cartfile.lock` file ensures that any given commit of a Carthage project can be bootstrapped in exactly the same way, every time. For this reason, you are **strongly recommended** to commit this file to your repository.

Although the `Cartfile.lock` file is meant to be human-readable and diffable, you **must not** modify it. The format of the file is very strict, and the order in which dependencies are listed is important for the build process.

## Carthage.build

This folder is created by `carthage build` in the project’s working directory, and contains the binary frameworks built for each dependency.

Generally, it is not necessary to commit this folder to your repository, so you may want to add it to your `.gitignore` file.

## Carthage.checkout

This folder is created by `carthage checkout` in the application project’s working directory, and contains the source code (at the appropriate version) for each dependency. The project folders inside `Carthage.checkout` are later used for the `carthage build` command.

You are not required to commit this folder to your repository, but you may wish to, if you want to guarantee that the chosen versions of each dependency will _always_ be accessible at a later date.

Unless you are [using submodules](#with-submodules), the contents of **this directory should not be modified**, as they may be overwritten by a future `carthage checkout` command.

### With submodules

If the `--use-submodules` flag was given when a project’s dependencies were bootstrapped, updated, or checked out, the dependencies inside `Carthage.checkout` will be available as Git submodules. This allows you to make changes in the dependencies, and commit and push those changes upstream.

## ~/.carthage/dependencies

This folder is created by `carthage checkout`, and contains the “bare” Git repositories used for fetching and checking out dependencies. Keeping all repositories in this centralized location avoids polluting individual projects with Git metadata, and allows Carthage to share one copy of each repository across all projects.

If you need to reclaim disk space, you can safely delete this folder, or any of its repository folders inside. The folder will be automatically repopulated the next time `carthage checkout` is run.
