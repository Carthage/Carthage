import Foundation

class ObjectWithLazyProperty {
    init() {}
    lazy var value: String = "hello"
    lazy var anotherValue: String = { return "world" }()
}
