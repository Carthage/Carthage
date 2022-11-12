# Artifacts

This document lists all files and folders used or created by Carthage, and the purpose of each.

## Cartfile

A `Cartfile` describes your project’s dependencies to Carthage, allowing it to resolve and build them for you. Cartfiles are a restricted subset of the [Ordered Graph Data Language](http://ogdl.org/), and any standard OGDL tool should be able to parse them.

Dependency specifications consist of two main parts: the [origin](#origin), and the [version requirement](#version-requirement).

#### Origin

The three supported origins right now are GitHub repositories, Git repositories, and binary-only frameworks served over `https`. Other possible origins may be added in the future. If there’s something specific you’d like to see, please [file an issue](https://github.com/Carthage/Carthage/issues/new).

##### GitHub Repositories

GitHub repositories (both GitHub.com and GitHub Enterprise) are specified with the `github` keyword:

```
github "ReactiveCocoa/ReactiveCocoa" # GitHub.com
github "https://enterprise.local/ghe/desktop/git-error-translations" # GitHub Enterprise
```

`github` origin is for specifying by `owner/repo` form or using prebuilt binary download feature through its web API, so using `git` or `ssh` protocol for `github` origin does not make sense and will be an error.

##### Git repositories

Other Git repositories are specified with the `git` keyword:

```
git "https://enterprise.local/desktop/git-error-translations2.git"
```

##### Binary only frameworks

Dependencies that are only available as compiled binary `.framework`s are specified with the `binary` keyword and as an `https://` URL, a `file://` URL, or a relative or an absolute path with no scheme, that returns a [binary project specification](#binary-project-specification):

```
binary "https://my.domain.com/release/MyFramework.json"   // Remote Hosted
binary "file:///some/Path/MyFramework.json"               // Locally hosted at file path
binary "relative/path/MyFramework.json"                   // Locally hosted at relative path to CWD
binary "/absolute/path/MyFramework.json"                  // Locally hosted at absolute path
```

When downloading a binary only frameworks, `carthage` will take into account the user's `~/.netrc` file to determine authentication credentials if `--use-netrc` flag was set.

#### Version requirement

Carthage supports several kinds of version requirements:

1. `>= 1.0` for “at least version 1.0”
1. `~> 1.0` for “compatible with version 1.0”
1. `== 1.0` for “exactly version 1.0”
1. `"some-branch-or-tag-or-commit"` for a specific Git object (anything allowed by `git rev-parse`).  **Note**: This form of requirement is _not_ supported for `binary` origins.

If no version requirement is given, any version of the dependency is allowed.

Compatibility is determined according to [Semantic Versioning](http://semver.org/). This means that any version greater than or equal to 1.5.1, but less than 2.0, will be considered “compatible” with 1.5.1.

According to SemVer, any 0.x.y release may completely break the exported API, so it's not safe to consider them compatible with one another. Only patch versions are compatible under 0.x, meaning 0.1.1 is compatible with 0.1.2, but not 0.2. This isn't according to the SemVer spec but keeps `~>` useful for 0.x.y versions.

**In all cases, Carthage will pin to a tag or SHA (for `git` and `github` origins) or a semantic version (for `binary` origins)**, and only bump those values when `carthage update` is run again in the future. This means that following a branch (for example) still results in commits that can be independently checked out just as they were originally.

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

# Use the branch
github "jspahrsummers/xcconfigs" "branch"

# Use a project from GitHub Enterprise
github "https://enterprise.local/ghe/desktop/git-error-translations"

# Use a project from any arbitrary server, on the "development" branch
git "https://enterprise.local/desktop/git-error-translations2.git" "development"

# Use a local project
git "file:///directory/to/project" "branch"

# A binary only framework
binary "https://my.domain.com/release/MyFramework.json" ~> 2.3

# A binary only framework via file: url
binary "file:///some/local/path/MyFramework.json" ~> 2.3

# A binary only framework via local relative path from Current Working Directory to binary project specification
binary "relative/path/MyFramework.json" ~> 2.3

# A binary only framework via absolute path to binary project specification
binary "/absolute/path/MyFramework.json" ~> 2.3
```

## Cartfile.private

Frameworks that want to include dependencies via Carthage, but do _not_ want to force those dependencies on parent projects, can list them in the optional `Cartfile.private` file, identically to how they would be specified in the main [Cartfile](#cartfile).

Anything listed in the private Cartfile will not be seen by dependent (parent) projects, which is useful for dependencies that may be important during development, but not when building releases—for example, test frameworks.

## Cartfile.resolved

After running the `carthage update` command, a file named `Cartfile.resolved` will be created alongside the `Cartfile` in the working directory. This file specifies precisely _which_ versions were chosen of each dependency, and lists all dependencies (even nested ones).

The `Cartfile.resolved` file ensures that any given commit of a Carthage project can be bootstrapped in exactly the same way, every time. For this reason, you are **strongly recommended** to commit this file to your repository.

Although the `Cartfile.resolved` file is meant to be human-readable and diffable, you **must not** modify it. The format of the file is very strict, and the order in which dependencies are listed is important for the build process.

## Carthage/Build

This folder is created by `carthage build` in the project’s working directory, and contains the binary frameworks and debug information for each dependency (whether built from scratch or downloaded).

You are not required to commit this folder to your repository, but you may wish to, if you want to guarantee that the built versions of each dependency will _always_ be accessible at a later date.

## Carthage/Checkouts

This folder is created by `carthage checkout` in the application project’s working directory, and contains your dependencies’ source code (when prebuilt binaries are not available). The project folders inside `Carthage/Checkouts` are later used for the `carthage build` command.

You are not required to commit this folder to your repository, but you may wish to, if you want to guarantee that the source checkouts of each dependency will _always_ be accessible at a later date.

Unless you are [using submodules](#with-submodules), the contents of **this directory should not be modified**, as they may be overwritten by a future `carthage checkout` command.

### With submodules

If the `--use-submodules` flag was given when a project’s dependencies were bootstrapped, updated, or checked out, the dependencies inside `Carthage/Checkouts` will be available as Git submodules. This allows you to make changes in the dependencies, and commit and push those changes upstream.

## ~/Library/Caches/org.carthage.CarthageKit

This folder is created automatically by Carthage, and contains the “bare” Git repositories used for fetching and checking out dependencies, as well as prebuilt binaries that have been downloaded. Keeping all repositories in this centralized location avoids polluting individual projects with Git metadata, and allows Carthage to share one copy of each repository across all projects.

If you need to reclaim disk space, you can safely delete this folder, or any of the individual folders inside. The folder will be automatically repopulated the next time `carthage checkout` is run.

## Binary Project Specification

For dependencies that do not have source code available, a binary project specification can be used to list the locations and versions of compiled frameworks.  This data **must** be available via `https` and could be served from a static file or dynamically.

* The JSON specification file name **should** have the same name as the framework and **not** be named **Carthage.json**, (example: MyFramework.json).
* The JSON structure is a top-level dictionary with the key-value pairs of version / location.
* The version **must** be a semantic version.  Git branches, tags and commits are not valid.
* The location **must** be an `https` url.

#### Publish an XCFramework build alongside the framework build using an `alt=` query parameter

To support users who build with `--use-xcframework`, create two zips: one containing the framework bundle(s) for your dependency, the other containing xcframework(s). Include "framework" or "xcframework" in the names of the zips, for example:  `MyFramework.framework.zip` and `MyFramework.xcframework.zip`. In your project specification, join the two URLs into one using a query string:

	https://my.domain.com/release/1.0.0/MyFramework.framework.zip?alt=https://my.domain.com/release/1.0.0/MyFramework.xcframework.zip

Starting in version 0.38.0, Carthage extracts any `alt=` URLs from the version specification. When `--use-xcframeworks` is passed, it prefers downloading URLs with "xcframework" in the name.

**For backwards compatibility,** provide the plain frameworks build _first_ (i.e. not as an alt URL), so that older versions of Carthage use it. Carthage versions prior to 0.38.0 fail to download and extract XCFrameworks.

#### Example binary project specification

```
{
	"1.0": "https://my.domain.com/release/1.0.0/framework.zip",
	"1.0.1": "https://my.domain.com/release/1.0.1/MyFramework.framework.zip?alt=https://my.domain.com/release/1.0.1/MyFramework.xcframework.zip"
}

```
