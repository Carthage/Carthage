#!/usr/bin/env PATH=/usr/bin /bin/zsh -r -e

[ $# -eq 0 ] || { print 'Invalid arguments.' > /dev/stderr; exit 22 }

local source_path="$(xcode-select --print-path)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include"

find -P ${source_path:?} -ipath '*arm*/types.h' -print0 | awk '
BEGIN {
  RS = "\0"
  split("", match_array, ":")
  first_query = "^.*if defined[^\w]__arm64__[^\w]$"
  second_query = "^[[:space:]]*typedef[[:space:]]+u_int64_t[[:space:]]"
} {
  RS = "\n"
  while(( getline line<$0) > 0 ) {
	if ( line ~ first_query ) { match_array[0] = line; continue }
	if ( length(match_array[0]) > 0 && line ~ second_query ) {
	  printf "--arch x86_64 --arch arm64"; exit 0
	} else { split("", match_array, ":") }
  }
  RS = "\0"
}
'

# 〜 Note: As intended, no newline output from the awk run.

# 〜 ‹-r› flag enables safety of restricted shell —
# 〜〜 see <http://zsh.sourceforge.net/Doc/Release/Invocation.html#Restricted-Shell>.
