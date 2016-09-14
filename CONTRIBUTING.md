We love that you’re interested in contributing to Carthage!

## Carthage is simple

Please file issues or submit pull requests for anything you’d like to see! However, we make no promises that they’ll be accepted—many suggestions will be rejected to preserve simplicity.

## Prefer pull requests

If you know exactly how to implement the feature being suggested or fix the bug being reported, please open a pull request instead of an issue. Pull requests are easier than patches or inline code blocks for discussing and merging the changes.

If you can’t make the change yourself, please open an issue after making sure that one isn’t already logged.

## Target CarthageKit

Unless you’re specifically improving something about the command-line experience of Carthage, please make code changes to [CarthageKit](README.md#carthagekit). This framework increases modularity, and allows other tools to integrate with Carthage more easily.

## Get started

After checkout, you can run the following command from the cloned directory, and then open the workspace in Xcode:

```bash
make bootstrap
```

Then, to install your development copy of Carthage (and any local changes you've made) on your system, and test with your own repos:

```bash
make install
```

If you want to go back to the mainline Brew build, just uninstall the dev copy first:

```bash
sudo make uninstall
brew install carthage
```

## Code style

If you’re interested in contributing code, please have a look at our [style guide](https://github.com/github/swift-style-guide), which we try to match fairly closely.

If you have a case that is not covered in the style guide, simply do your best to match the style of the surrounding code.

**Thanks for contributing! :boom::camel:**
