//
//  World.swift
//  Quick
//
//  Created by Brian Ivan Gesiak on 6/5/14.
//  Copyright (c) 2014 Brian Ivan Gesiak. All rights reserved.
//

import Foundation

public typealias SharedExampleContext = () -> (NSDictionary)
public typealias SharedExampleClosure = (SharedExampleContext) -> ()

public class World: NSObject {
    typealias BeforeSuiteClosure = () -> ()
    typealias AfterSuiteClosure = BeforeSuiteClosure

    var _specs: Dictionary<String, ExampleGroup> = [:]

    var _beforeSuites = [BeforeSuiteClosure]()
    var _beforeSuitesNotRunYet = true

    var _afterSuites = [AfterSuiteClosure]()
    var _afterSuitesNotRunYet = true

    var _sharedExamples: [String: SharedExampleClosure] = [:]

    public var currentExampleGroup: ExampleGroup?

    struct _Shared {
        static let instance = World()
    }
    public class func sharedWorld() -> World {
        return _Shared.instance
    }

    public func rootExampleGroupForSpecClass(cls: AnyClass) -> ExampleGroup {
        let name = NSStringFromClass(cls)
        if let group = _specs[name] {
            return group
        } else {
            let group = ExampleGroup("root example group")
            _specs[name] = group
            return group
        }
    }

    func runBeforeSpec() {
        assert(_beforeSuitesNotRunYet, "runBeforeSuite was called twice")
        for beforeSuite in _beforeSuites {
            beforeSuite()
        }
        _beforeSuitesNotRunYet = false
    }

    func runAfterSpec() {
        assert(_afterSuitesNotRunYet, "runAfterSuite was called twice")
        for afterSuite in _afterSuites {
            afterSuite()
        }
        _afterSuitesNotRunYet = false
    }

    func appendBeforeSuite(closure: BeforeSuiteClosure) {
        _beforeSuites.append(closure)
    }

    func appendAfterSuite(closure: AfterSuiteClosure) {
        _afterSuites.append(closure)
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
