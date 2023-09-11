#!/bin/zsh --no-globalrcs --no-rcs

# if the new linker is there, then `dirname $(xcrun --find swift))/../lib/swift_static/macosx` should not be respected as the sentinel value it held in pre-«Xcode 15» days.
# In a subsequent script — the Makefile — we look for '^only one snapshot supported' (which only exists in the old linker) to tell us.
## See <https://github.com/apple-opensource/ld64/blame/8568ce3517546665f1f9e0f7ba1858889a305454/src/ld/Snapshot.cpp> for the old linker.
## See <https://github.com/apple-oss-distributions/dyld/> for the new linker.

(/usr/bin/xcrun --find ld | /usr/bin/xargs /usr/bin/strings) || true
