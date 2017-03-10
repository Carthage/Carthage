#!/usr/bin/env bats

git-commit() {
	git add --all && git commit --author='Carthage Integration Tests <>' -m "${1:?}"
}
