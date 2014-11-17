class Poet: Person {
    override var greeting: String {
        get {
            if isHappy {
                return "Oh, joyous day!"
            } else {
                return "Woe is me!"
            }
        }
    }
}
