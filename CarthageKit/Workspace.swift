//  Copyright (c) 2014 Carthage. All rights reserved.

import Foundation

public final class Box<T> {
	public init(_ value: T) {
		self.value = value
	}
	public var value: T
}

public enum Either<T, U> {
	case Left(Box<T>)
	case Right(Box<U>)
}

public func script() -> Either<NSDictionary?, ScriptResult?> {
	func tell(script: [String]) -> NSAppleScript? {
		return NSAppleScript(source: "tell application \"Xcode\"\n" + join("\n", script) + "\nend tell")
	}

	var error: NSDictionary?
	if let script = tell(["projects"]) {
		if script.compileAndReturnError(&error) {
			if let descriptor = script.executeAndReturnError(&error) {
				return .Right(Box(Optional(ScriptResult(descriptor))))
			}
			return .Right(Box(nil))
		}
	}
	return .Left(Box(error))
}

extension NSAppleEventDescriptor {
	var descriptors: [NSAppleEventDescriptor?] {
		var descriptors = [NSAppleEventDescriptor?]()
		for index in (0..<self.numberOfItems) {
			descriptors.append(self.descriptorAtIndex(index))
		}
		return descriptors
	}
}

public enum ScriptResult: Printable {
	case Nil
	case Boolean(BooleanType)
	case Integer(Int)
	case String(Swift.String?)
	case List([ScriptResult])

	private init(_ descriptor: NSAppleEventDescriptor?) {
		if let d = descriptor {
			let descriptorType = d.descriptorType
			switch Int(d.descriptorType) {
			case typeBoolean: self = Boolean(d.booleanValue != 0)
			case typeSInt16, typeUInt16, typeSInt32, typeUInt32, typeSInt64, typeUInt64: self = Integer(Int(d.int32Value))
			case typeUTF8Text, typeUTF16ExternalRepresentation: self = String(d.stringValue)
			case typeAEList:
				self = List(map(d.descriptors) { ScriptResult($0) })
			default: self = Nil
			}
		}
		self = Nil
	}

	public var description: Swift.String {
		switch self {
		case Nil: return "nil"
		case let Boolean(x): return toString(x.boolValue)
		case let String(s): return s ?? "nil as String?"
		case let Integer(x): return toString(x)
		default: return "unprintable"
		}
	}
}
