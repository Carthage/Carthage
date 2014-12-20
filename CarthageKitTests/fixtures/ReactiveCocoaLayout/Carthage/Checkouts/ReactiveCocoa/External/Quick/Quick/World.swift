import Foundation

public typealias SharedExampleContext = () -> (NSDictionary)
public typealias SharedExampleClosure = (SharedExampleContext) -> ()

public class World: NSObject {
    var _specs: Dictionary<String, ExampleGroup> = [:]
    var _sharedExamples: [String: SharedExampleClosure] = [:]

    let _configuration = Configuration()
    var _isConfigurationFinalized = false

    internal var exampleHooks: ExampleHooks {return _configuration.exampleHooks }
    internal var suiteHooks: SuiteHooks { return _configuration.suiteHooks }

    /**
        Exposes the World's Configuration object within the scope of the closure
        so that it may be configured. This method must not be called outside of
        an overridden +[QuickConfiguration configure:] method.

        :param: closure  A closure that takes a Configuration object that can
                         be mutated to change Quick's behavior.
    */
    public func configure(closure: QuickConfigurer) {
        assert(!_isConfigurationFinalized,
               "Quick cannot be configured outside of a +[QuickConfiguration configure:] method. You should not call -[World configure:] directly. Instead, subclass QuickConfiguration and override the +[QuickConfiguration configure:] method.")
        closure(configuration: _configuration)
    }

    /**
        Finalizes the World's configuration.
        Any subsequent calls to World.configure() will raise.
    */
    public func finalizeConfiguration() {
        _isConfigurationFinalized = true
    }

    public var currentExampleGroup: ExampleGroup?

    public var isRunningAdditionalSuites = false

    public func rootExampleGroupForSpecClass(cls: AnyClass) -> ExampleGroup {
        let name = NSStringFromClass(cls)
        if let group = _specs[name] {
            return group
        } else {
            let group = ExampleGroup(description: "root example group",
                                     isInternalRootExampleGroup: true)
            _specs[name] = group
            return group
        }
    }

    var exampleCount: Int {
        get {
            var count = 0
            for (_, group) in _specs {
                group.walkDownExamples { (example: Example) -> () in
                    _ = ++count
                }
            }
            return count
        }
    }

    func registerSharedExample(name: String, closure: SharedExampleClosure) {
        _raiseIfSharedExampleAlreadyRegistered(name)
        _sharedExamples[name] = closure
    }

    func _raiseIfSharedExampleAlreadyRegistered(name: String) {
        if _sharedExamples[name] != nil {
            NSException(name: NSInternalInconsistencyException,
                reason: "A shared example named '\(name)' has already been registered.",
                userInfo: nil).raise()
        }
    }

    func sharedExample(name: String) -> SharedExampleClosure {
        _raiseIfSharedExampleNotRegistered(name)
        return _sharedExamples[name]!
    }

    func _raiseIfSharedExampleNotRegistered(name: String) {
        if _sharedExamples[name] == nil {
            NSException(name: NSInternalInconsistencyException,
                reason: "No shared example named '\(name)' has been registered. Registered shared examples: '\(Array(_sharedExamples.keys))'",
                userInfo: nil).raise()
        }
    }
}
