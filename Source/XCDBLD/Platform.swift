import Foundation

/*
Former file of `XCDBLD.Platform` — previously, platform functioned as somewhat of a
simulator-removed instance of an SDK.

This is dissimilar (in spirit and practice) to how Xcode Build Settings and
`xcodebuild -showsdks -json` employed the term `Platform`.

Functionality previously provided by this type is mostly now accomodated by
`SDK.platformSimulatorlessFromHeuristic`.
*/
