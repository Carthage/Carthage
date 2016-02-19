import Cocoa

func spinForTestIfNecessary() {
	if NSClassFromString("XCTestCase") != nil {
		NSApplicationMain(Process.argc, Process.unsafeArgv)
	}
}