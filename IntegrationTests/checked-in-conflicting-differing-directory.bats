#!/usr/bin/env bats

load "Utilities/git-commit"
load "Utilities/TestFramework"

### older version of carthage wrote this directory?
### user wrote this directory, unaware of the precedent not to circumvent carthage’s management?
### directory exists as the result of rogue process or gamma ray?

### TODO: explore possibility of messaging user, informing that deleting said directory will result
### in symlink creation with carthage versions greater than 0.20.0, maybe with more broad advice on
### “from scratch” reproducability.

extracted_directory="${BATS_TMPDIR}/DependencyTest"

project_directory() {
	if [[ -z ${CI+x} ]]; then
		echo -n "${BATS_TMPDIR:?}"
	else
		echo -n "${HOME:?}/Library/Caches/org.carthage.CarthageIntegration"
	fi

	echo -n "/IntegrationTestProject"
}

setup() {
	extract-test-frameworks-one-and-two

	export GITCONFIG='/dev/null'
	branch-test-frameworks-one-and-two 'checked-in-conflicting-differing-directory'

	cd ${extracted_directory}/SourceRepos/TestFramework1

	mkdir -p ${PWD}/'Carthage/Checkouts'
	ditto 'TestFramework1.xcodeproj/project.xcworkspace/' 'Carthage/Checkouts/TestFramework2'
	git-commit 'Add (for nonsensical reasons) conflicting directory at «Carthage/Checkouts/TestFramework2».'

	mkdir -p "$(project_directory)" && cd "$(project_directory)"

	cat > Cartfile <<-EOF
		git "file://${extracted_directory}/SourceRepos/TestFramework1" "checked-in-conflicting-differing-directory"
	EOF

	# Optionally, only if environment variable `CARTHAGE_INTEGRATION_CLEAN_DEPENDENCIES_CACHE` is manually set:
	[[ -n ${CARTHAGE_INTEGRATION_CLEAN_DEPENDENCIES_CACHE+x} ]] || rm -rf ~/Library/Caches/org.carthage.CarthageKit/dependencies/
}

teardown() {
	[[ ! -d "$(project_directory)" ]] || rm -rf "$(project_directory)"
	[[ ! -d ${extracted_directory} ]] || rm -rf ${extracted_directory}
	cd $BATS_TEST_DIRNAME
}

carthage-and-check-project-directory() {
	carthage $@
	[[ -d "$(project_directory)/Carthage/Checkouts/TestFramework1/Carthage/Checkouts/TestFramework2" ]]
}

@test "with conflicting checked-in directory in «Carthage/Checkouts» of dependency, carthage bootstrap should avoid writing there" {
	carthage-and-check-project-directory bootstrap --no-build --no-use-binaries
}

@test "with conflicting checked-in directory in «Carthage/Checkouts» of dependency, carthage «bootstrap, update, update» should avoid writing there" {
	carthage-and-check-project-directory bootstrap --no-build --no-use-binaries

	carthage-and-check-project-directory update --no-build --no-use-binaries

	carthage-and-check-project-directory update --no-build --no-use-binaries
}

@test "with conflicting checked-in directory in «Carthage/Checkouts» of dependency of git-controlled project, carthage bootstrap should avoid writing there" {
	echo 'Carthage/Build' > .gitignore
	git init && git-commit 'Initialize project.'

	carthage-and-check-project-directory bootstrap --no-build --no-use-binaries
}
