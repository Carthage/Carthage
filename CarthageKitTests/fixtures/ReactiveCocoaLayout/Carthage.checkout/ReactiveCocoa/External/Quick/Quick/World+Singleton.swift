extension World {
    struct _Shared {
        static let instance = World()
    }
    public class func sharedWorld() -> World {
        return _Shared.instance
    }
}
