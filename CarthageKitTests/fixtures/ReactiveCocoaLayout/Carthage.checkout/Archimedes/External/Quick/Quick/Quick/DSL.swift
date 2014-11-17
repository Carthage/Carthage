//
//  DSL.swift
//  Quick
//
//  Created by Brian Ivan Gesiak on 6/5/14.
//  Copyright (c) 2014 Brian Ivan Gesiak. All rights reserved.
//

import Foundation

@objc public class DSL {
    public class func beforeSuite(closure: () -> ()) {
        World.sharedWorld().appendBeforeSuite(closure)
    }

    public class func afterSuite(closure: () -> ()) {
        World.sharedWorld().appendAfterSuite(closure)
    }

    public class func sharedExamples(name: String, closure: SharedExampleClosure) {
        World.sharedWorld().registerSharedExample(name, closure: closure)
    }

    public class func describe(description: String, closure: () -> ()) {
        var group = ExampleGroup(description)
        World.sharedWorld().currentExampleGroup!.appendExampleGroup(group)
        World.sharedWorld().currentExampleGroup = group
        closure()
        World.sharedWorld().currentExampleGroup = group.parent
    }

    public class func context(description: String, closure: () -> ()) {
        self.describe(description, closure: closure)
    }

    public class func beforeEach(closure: () -> ()) {
        World.sharedWorld().currentExampleGroup!.appendBefore { (exampleMetadata: ExampleMetadata) in
            closure()
        }
    }

    public class func beforeEach(#closure: (exampleMetadata: ExampleMetadata) -> ()) {
        World.sharedWorld().currentExampleGroup!.appendBefore(closure)
    }

    public class func afterEach(closure: () -> ()) {
        World.sharedWorld().currentExampleGroup!.appendAfter { (exampleMetadata: ExampleMetadata) in
            closure()
        }
    }

    public class func afterEach(#closure: (exampleMetadata: ExampleMetadata) -> ()) {
        World.sharedWorld().currentExampleGroup!.appendAfter(closure)
    }

    public class func it(description: String, file: String, line: Int, closure: () -> ()) {
        let callsite = Callsite(file: file, line: line)
        let example = Example(description, callsite, closure)
        World.sharedWorld().currentExampleGroup!.appendExample(example)
    }

    public class func itBehavesLike(name: String, sharedExampleContext: SharedExampleContext, file: String, line: Int) {
        let callsite = Callsite(file: file, line: line)
        let closure = World.sharedWorld().sharedExample(name)

        var group = ExampleGroup(name)
        World.sharedWorld().currentExampleGroup!.appendExampleGroup(group)
        World.sharedWorld().currentExampleGroup = group
        closure(sharedExampleContext)
        World.sharedWorld().currentExampleGroup!.walkDownExamples { (example: Example) in
            example.isSharedExample = true
            example.callsite = callsite
        }

        World.sharedWorld().currentExampleGroup = group.parent
    }

    public class func pending(description: String, closure: () -> ()) {
        NSLog("Pending: %@", description)
    }
}

public func beforeSuite(closure: () -> ()) {
    DSL.beforeSuite(closure)
}

public func afterSuite(closure: () -> ()) {
    DSL.afterSuite(closure)
}

public func sharedExamples(name: String, closure: () -> ()) {
    DSL.sharedExamples(name, closure: { (NSDictionary) in closure() })
}

public func sharedExamples(name: String, closure: SharedExampleClosure) {
    DSL.sharedExamples(name, closure: closure)
}

public func describe(description: String, closure: () -> ()) {
    DSL.describe(description, closure: closure)
}

public func context(description: String, closure: () -> ()) {
    describe(description, closure)
}

public func beforeEach(closure: () -> ()) {
    DSL.beforeEach(closure)
}

public func beforeEach(#closure: (exampleMetadata: ExampleMetadata) -> ()) {
    DSL.beforeEach(closure: closure)
}

public func afterEach(closure: () -> ()) {
    DSL.afterEach(closure)
}

public func afterEach(#closure: (exampleMetadata: ExampleMetadata) -> ()) {
    DSL.afterEach(closure: closure)
}

public func it(description: String, closure: () -> (), file: String = __FILE__, line: Int = __LINE__) {
    DSL.it(description, file: file, line: line, closure: closure)
}

public func itBehavesLike(name: String, file: String = __FILE__, line: Int = __LINE__) {
    itBehavesLike(name, { return [:] }, file: file, line: line)
}

public func itBehavesLike(name: String, sharedExampleContext: SharedExampleContext, file: String = __FILE__, line: Int = __LINE__) {
    DSL.itBehavesLike(name, sharedExampleContext: sharedExampleContext, file: file, line: line)
}

public func pending(description: String, closure: () -> ()) {
    DSL.pending(description, closure: closure)
}

public func xdescribe(description: String, closure: () -> ()) {
    pending(description, closure)
}

public func xcontext(description: String, closure: () -> ()) {
    pending(description, closure)
}

public func xit(description: String, closure: () -> ()) {
    pending(description, closure)
}
