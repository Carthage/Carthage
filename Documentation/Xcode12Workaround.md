# Using Carthage with Xcode 12

As Carthage doesn't work out of the box with Xcode 12, this document will guide through a workaround that works for most cases.

## Why Carthage compilation fails

Well, shortly, Carthage builds fat frameworks, which means that the framework contains binaries for all supported architectures. 
Until Apple Sillicon was introduced it all worked just fine, but now there is a conflict as there are duplicate architectures (arm64 for devices and arm64 for simulator).
This means that Carthage cannot link architecture specific frameworks to a single fat framework.

You can find more info in [respective issue #3019](https://github.com/Carthage/Carthage/issues/3019).

## Workaround 

As a workaround you can invoke carthage using this script, it will remove the arm64 architecture for simulator, so the above mentioned conflict doesn't exist.

## How to make it work

1. place this script somewhere to your `PATH` (I personally have it in `/usr/local/bin/carthage.sh`)
2. make it the script executable, so open your _Terminal_ and run 
   ```bash
   chmod +x /usr/local/bin/carthage.sh
   ```
3. from now on instead of running e.g. 
   ```
   carthage bootstrap --platform iOS --cache-builds
   ```
   you need to run our script
   ```
   carthage.sh bootstrap --platform iOS --cache-builds
   ```

### Workaround script

This script has a known limitation - it will remove arm64 simulator architecture from compiled framework, so frameworks compiled using it cannot be used on Macs running Apple Silicon.

```bash
# carthage.sh
# Usage example: ./carthage.sh build --platform iOS

set -euo pipefail

xcconfig=$(mktemp /tmp/static.xcconfig.XXXXXX)
trap 'rm -f "$xcconfig"' INT TERM HUP EXIT

# For Xcode 12 make sure EXCLUDED_ARCHS is set to arm architectures otherwise
# the build will fail on lipo due to duplicate architectures.

CURRENT_XCODE_VERSION=$(xcodebuild -version | grep "Build version" | cut -d' ' -f3)
echo "EXCLUDED_ARCHS__EFFECTIVE_PLATFORM_SUFFIX_simulator__NATIVE_ARCH_64_BIT_x86_64__XCODE_1200__BUILD_$CURRENT_XCODE_VERSION = arm64 arm64e armv7 armv7s armv6 armv8" >> $xcconfig

echo 'EXCLUDED_ARCHS__EFFECTIVE_PLATFORM_SUFFIX_simulator__NATIVE_ARCH_64_BIT_x86_64__XCODE_1200 = $(EXCLUDED_ARCHS__EFFECTIVE_PLATFORM_SUFFIX_simulator__NATIVE_ARCH_64_BIT_x86_64__XCODE_1200__BUILD_$(XCODE_PRODUCT_BUILD_VERSION))' >> $xcconfig
echo 'EXCLUDED_ARCHS = $(inherited) $(EXCLUDED_ARCHS__EFFECTIVE_PLATFORM_SUFFIX_$(EFFECTIVE_PLATFORM_SUFFIX)__NATIVE_ARCH_64_BIT_$(NATIVE_ARCH_64_BIT)__XCODE_$(XCODE_VERSION_MAJOR))' >> $xcconfig

export XCODE_XCCONFIG_FILE="$xcconfig"
carthage "$@"
```
