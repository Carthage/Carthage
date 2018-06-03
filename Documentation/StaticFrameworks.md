# Build static frameworks to speed up your app’s launch times
Carthage supports building static frameworks in place of dynamic frameworks when used in concert with Keith Smiley’s `ld.py` script, published [here](https://github.com/keith/swift-staticlibs/blob/master/ld.py). If you have many dynamic frameworks, you may have noticed that your application's launch times can be quite slow relative to other applications. To mitigate this, Apple suggests that you embed [at most six dynamic frameworks](https://developer.apple.com/videos/play/wwdc2016/406/?time=1794) into your applications. Unfortunately, Xcode has not supported building static Swift frameworks out of the box since Apple made that recommendation, so it is a bit tricky to follow this advice. The goal of this guide is to show you how to reduce the number of embedded dynamic frameworks in your application with some simple wrappers around Carthage.

Since you’re going to be rebuilding dynamic frameworks as static frameworks, make sure that when you perform a `carthage checkout`,  `carthage bootstrap`, or `carthage update` from this point forward, you are supplying the `--no-use-binaries` flag to `carthage`. This will ensure that Carthage doesn’t download prebuilt dynamic frameworks and place them into your `Carthage/Build` directory, since you won’t be needing them anyways.

To build static frameworks with Carthage, we suggest wrapping invocations of `carthage build` with a script that looks something like this:

```bash
#!/bin/sh -e

xcconfig=$(mktemp /tmp/static.xcconfig.XXXXXX)
trap 'rm -f "$xcconfig"' INT TERM HUP EXIT

echo "LD = $PWD/the/path/to/ld.py" >> $xcconfig
echo "DEBUG_INFORMATION_FORMAT = dwarf" >> $xcconfig

export XCODE_XCCONFIG_FILE="$xcconfig"

carthage build "$@"
```

This script ensures that whenever you invoke `carthage build` , there’s a temporary `.xcconfig` file that’s provided to Carthage’s invocations of `xcodebuild` that forces it to build dynamic frameworks as static frameworks by replacing the `ld` command with invocations to `libtool` instead. It additionally makes sure that `xcodebuild`  does not attempt to produce `dSYM` files for static frameworks, since this would cause a build failure otherwise. Finally, this script also ensures that the temporary `xcconfig` file is automatically deleted whenever the script exits. After you've modified this script to suit your needs, don’t forget to make it executable via `chmod +x`.

Note that you’ll also need to download [ld.py](https://github.com/keith/swift-staticlibs/blob/master/ld.py) and make it executable via `chmod +x ld.py` to invoke it in the above script. It would probably make sense to check it into your repository, but that’s ultimately up to you.

Once you’ve modified the above script to fit your local directory structure and added `ld.py` to a location in your repository, you should be able to build static frameworks with Carthage now by invoking your script from above, e.g.:
```bash
./carthage-build-static.sh ReactiveCocoa --platform ios
```

To double-check that Carthage is building static frameworks, you can inspect the binary of one of your frameworks in the `Carthage/Build` folder:
```bash
file Carthage/Build/iOS/ReactiveCocoa.framework/ReactiveCocoa
```
If the output includes `current ar archive`, congratulations—you’ve just built a static framework using Carthage. If you see `Mach-O dynamically linked shared library`, something went wrong with your script—please double-check that you’ve followed the instructions above.

Now that you have Carthage building static frameworks, there are two ways to integrate them into your existing projects:

## Linking many static frameworks into your application binary
If you’re linking static frameworks into your existing application, it should be as simple as dragging and dropping the `.framework`s into the "Link Binary with Libraries" build phase, just as with dynamic frameworks. If you see any new failure, please refer to the below troubleshooting sections.

If you were previously building these frameworks as dynamic frameworks, make sure that you no longer embed them into your package's `Frameworks` folder via the `carthage copy-frameworks` command, as this step is not necessary with static frameworks.

## Merging your static frameworks into a single larger dynamic framework
If your application has plugins or app extensions that need to share many frameworks, it may work best to merge many static frameworks together into one larger dynamic framework to share effectively between your targets. To do so, create a framework target in your Xcode project that your application and each of the other relevant targets depend on. Then, drag and drop the static `.framework`s that you want to merge into this binary into the "Link Binary with Libraries" build step of this new merged framework target.

To ensure that this new merged framework is a true merge of all of its dependent static frameworks, you should include the `-all_load`  flag in its `OTHER_LDFLAGS` build setting. This forces the linker to merge the full static framework into the dynamic framework (rather than just the parts that are used by your merged framework). If you don’t do this, consumers of the merged framework will likely encounter linker errors with undefined symbols.

### Resolving linker warnings
At this stage, your targets probably have their `Framework Search Paths` pointed at the `Carthage/Build/iOS` folder which now contains static frameworks. So you will start seeing: `ld: warning: Auto-Linking supplied 'X.framework/X', framework linker option at X.framework/X is not a dylib` for each of them when you compile. Unfortunately "Auto-Linking" is inferring frameworks that are used from your source, but doesn't know that your larger dynamic framework is providing them, and looks in `Framework Search Paths` for them. It finds the statics, hence the warnings.

To work around this, you can point the targets that consume your large dynamic framework at a folder containing regular dynamic framework builds instead of the static ones. Your larger dynamic framework stuff points to the static ones though. This way Xcode knows what modules and symbols are available for the consumers, the linker will not actually auto-link to them because they are dylibs, but the linker also won't complain. The symbols are still provided by the larger dynamic frameowrk, which is loaded at app start. Note that this is a workaround, so use at your own risk!

Another linker warning you might faced with during large dynamic framework is: `ld: warning: Auto-Linking library not found for -lswiftCore`, as well as errors such as: `Undefined symbols for architecture x86_64: "Swift.String.init<A>(stringInterpolationSegment: A) -> Swift.String", referenced from:...`. To fix this issue you need to add an empty class withing this dynamic framework: `final class Empty {}`.

## Linker flags
If any of your frameworks contain Objective-C extensions, you will need to supply the `-ObjC` flag in your `OTHER_LDFLAGS` build setting to ensure that they’re successfully invoked. If you do not supply this flag, you will see a runtime crash whenever an Objective-C extension is invoked.

If any of your static frameworks require you to pass additional linker flags, you will see linker failures like `Undefined symbols for architecture arm64:`. In this case, you may need to pass some additional linker flags to get the static framework to link into your project. It should be obvious from the output which static framework is at fault. To find out which flags to include in the `OTHER_LDFLAGS` build setting of your project to fix the error, you should open the Xcode project for the framework causing the build failures and inspect the "Other linker flags" setting. In that build setting, you should be able to find additional linker flags you will need to provide to your project to fix the linker error.

## Embedded resources
If any of your dynamic frameworks contained embedded resources, you may not be able to build them statically. However, you may find success in just copying the resources into the bundle that you’re linking the static frameworks with, but this will not work in all cases.
