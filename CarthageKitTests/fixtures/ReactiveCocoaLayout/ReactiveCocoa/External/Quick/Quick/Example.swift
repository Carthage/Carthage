import XCTest

var _numberOfExamplesRun = 0

@objc public class Example {
    weak var group: ExampleGroup?

    var _description: String
    var _closure: () -> ()

    public var isSharedExample = false
    public var callsite: Callsite

    public var name: String {
        get {
            switch group!.name {
                case .Some(let groupName):
                    return "\(groupName), \(_description)"
                case .None:
                    return _description
            }
        }
    }

    init(_ description: String, _ callsite: Callsite, _ closure: () -> ()) {
        self._description = description
        self._closure = closure
        self.callsite = callsite
    }

    public func run() {
        let world = World.sharedWorld()

        if _numberOfExamplesRun == 0 {
            world.suiteHooks.executeBefores()
        }

        let exampleMetadata = ExampleMetadata(example: self, exampleIndex: _numberOfExamplesRun)
        world.exampleHooks.executeBefores(exampleMetadata)
        for before in group!.befores {
            before(exampleMetadata: exampleMetadata)
        }

        _closure()

        for after in group!.afters {
            after(exampleMetadata: exampleMetadata)
        }
        world.exampleHooks.executeAfters(exampleMetadata)

        ++_numberOfExamplesRun


        if !world.isRunningAdditionalSuites && _numberOfExamplesRun >= world.exampleCount {
            world.suiteHooks.executeAfters()
        }
    }
}
