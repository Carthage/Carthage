import CarthageKit
import Commandant
import Foundation
import Result
import Curry

/*
Former file of `carthage cleanup` command — which existed on-master, but unshipped-in-tags — and no longer makes sense when set of SDKs are non-fixed across Xcode versions.

See also <github.com/Carthage/Carthage/pull/2872> — and major thanks to @sidepelican and @chuganzy for developing it…
〜 sorry that the new system of dynamically parsed SDKs makes it nonviable; maybe it's viable in some future way…

See commit <github.com/Carthage/Carthage/commit/883f1c8e479ac10f5f38b367e6483517e4686383>.
*/
