
import Foundation

extension Collection where Element: Hashable {
    
    func unique() -> [Element] {
        var set = Set<Element>(minimumCapacity: count)

        return filter {
            return set.insert($0).inserted
        }
    }
}
