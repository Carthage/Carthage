import Foundation

class Person: NSObject {
    var isHappy = true
    var isHungry = false
    var isSatisfied = false
    var hopes = ["winning the lottery", "going on a blimp ride"]
    var smalltalk = "Come here often?"
    var valediction = "See you soon."

    var greeting: String {
        get {
            if isHappy {
                return "Hello!"
            } else {
                return "Oh, hi."
            }
        }
    }

    func eatChineseFood() {
        let after = dispatch_time(DISPATCH_TIME_NOW, 500000000)
        dispatch_after(after, dispatch_get_main_queue()) {
            self.isHungry = true
        }
    }
}
