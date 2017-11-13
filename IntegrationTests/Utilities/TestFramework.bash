#!/usr/bin/env bats

load "Utilities/git-commit"

extract-test-frameworks-one-and-two() {
	unzip ${BATS_TEST_DIRNAME:?}/../Tests/CarthageKitTests/fixtures/DependencyTest.zip 'DependencyTest/SourceRepos/TestFramework[12]/*' -d "${BATS_TMPDIR:?}"
}

branch-test-frameworks-one-and-two() {
	directory_to_return_into="${PWD:?}"
	branch="${1:?}" # parameter 1: branch name used in git repositories for both `TestFramework`s.

	# - - - - - - -

	cd ${extracted_directory:?}/SourceRepos/TestFramework2
	git checkout -b ${branch} master

	rm -v Cartfile Cartfile.resolved
	git-commit 'Remove dependencies.'

	# - - - - - - -

	cd ${extracted_directory:?}/SourceRepos/TestFramework1
	git checkout -b ${branch} master

	# overwrite Cartfile
	cat >| Cartfile <<-EOF
		git "file://${extracted_directory:?}/SourceRepos/TestFramework2" "${branch}"
	EOF

	rm -v Cartfile.resolved
	git-commit 'Set Cartfile based on file URLs and branch.'

	# - - - - - - -

	cd ${directory_to_return_into:?}
}
