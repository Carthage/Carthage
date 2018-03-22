# Releasing a New Version of Carthage
## 1. Create the Release Notes
Document what’s changed, keeping an eye out for breaking changes that will affect the version number.

Release notes typically follow this pattern:

> **Fixed**
> * Something was fixed (#pr-number). Thanks @pr-author!
> 
> **Added**
> * Something was added (#pr-number). Thanks @pr-author!
> 
> **Improved**
> * Something was improved (#pr-number). Thanks @pr-author!
> 
> Thank you to {authors of PRs that improved code quality} for improvements to the code base! Thank you to {reviewers of PRs} for reviewing pull requests!

Try to call out more important items earlier in the list.

You can use the [compare](https://github.com/Carthage/Carthage/compare) page on GitHub to see what’s changed since the previous release. Typically only the merge commits (those of the form _Merge pull request #2342 from branch-name_) are needed. Click the link to the PR to see what changed.

## 2. Update Version Number
If the changes in this release are breaking, then increment the minor number (`0.26.0` to `0.27.0`). Otherwise increment the patch number (`0.26.0` to `0.26.1`).

The version number needs to be set in the `CarthageKitVersion` struct and in the `Info.plist`s for both `carthage` and `CarthageKit`.

This commit can be made directly to `master` and then pushed to GitHub.

## 3. Create Draft Release
Create a [new release](https://github.com/Carthage/Carthage/releases/new) on GitHub. The tag version should always be 3 numbers (i.e. `0.26.0`, not `0.26`). Check _This is a pre-release_ for now.

## 4. Create Installer
Now that you’ve created the release, do a `git pull`: you need the tag locally when you create the installer.

Run `make package` to create the installer locally. It’s probably a good idea to install it and run `carthage version` to make sure that you’ve picked up the changes.

## 5. Publish Release
Edit the release you created. Add the `Carthage.pkg` and `CarthageKit.framework` that were created, uncheck _This in a pre-release_, and publish! Congratulations, you’ve published the release! 👏

## 6. Update Homebrew (optional)
Many people install Carthage with Homebrew. In order for them to upgrade, [the Homebrew formula](https://github.com/Homebrew/homebrew-core/blob/master/Formula/carthage.rb) needs to be updated.

Normally only `tag` and `revision` need to be updated in the formula. But if the supported Xcode versions have changed, that will need to be updated as well.
The `sha256` values will be automatically changed by homebrew once the bottles are ready.

Once you open a PR against the Homebrew repo, it’s typically merged within a few hours.
You can open a PR from your own fork or from [Carthage/homebrew-core](https://github.com/Carthage/homebrew-core).

