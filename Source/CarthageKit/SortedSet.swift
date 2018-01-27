//
// Created by Werner Altewischer on 27/01/2018.
// Copyright (c) 2018 Carthage. All rights reserved.
//

import Foundation

/**
A set which sorts its elements in natural order.

This type is intentionally modelled as a class instead of a struct to have control over when copies take place.
*/
public final class SortedSet<T: Comparable>: Sequence, Collection {

    public enum SearchResult {
        case found(index: Int) //The index
        case notFound(insertionIndex: Int) //The insertion index
    }

    public typealias Element = T
    public typealias Iterator = Array<Element>.Iterator
    public typealias Index = Int

    private var storage: [Element]

    /**
    Returns a copy of this set.
    */
    public var copy: SortedSet<Element> {
        let ret = SortedSet<Element>(storage: storage)
        return ret
    }

    private init(storage: [Element]) {
        self.storage = storage
    }

    public convenience init() {
        self.init(storage: [Element]())
    }

    /**
    Inserts an object at the correct insertion point to keep the set sorted,
    returns true if successful (i.e. the object did not yet exist), false otherwise.

    O(log(N))
    */
    @discardableResult
    public func insert(_ element: Element) -> Bool {
        let index = storage.binarySearch(element)

        if (index >= 0) {
            //Element already exists
            return false
        } else {
            let insertionIndex = -(index + 1)
            storage.insert(element, at: insertionIndex)
            return true
        }
    }

    /**
    Removes an object from the set,
    returns true if succesful (i.e. the set contained the object), false otherwise

    O(log(N))
    */
    @discardableResult
    public func remove(_ element: Element) -> Bool {
        let index = storage.binarySearch(element)
        if (index >= 0) {
            storage.remove(at: index)
            return true
        } else {
            return false
        }
    }

    /**
    Checks whether the specified object is contained in this set, returns true if so, false otherwise.

    O(log(N))
    */
    public func contains(_ element: Element) -> Bool {
        return storage.binarySearch(element) >= 0
    }

    /**
    Retains all objects satisfying the specified predicate.

    O(N)
    */
    public func retainAll(satisfying predicate: (Element) -> Bool) {
        var newStorage = [Element]()
        for obj in storage {
            if predicate(obj) {
                newStorage.append(obj)
            }
        }
        storage = newStorage
    }

    /**
    Retains the specified range, removes all other objects.
    */
    public func retain(range: Range<Int>) {
        let slice: ArraySlice<Element> = storage[range]
        storage = Array(slice)
    }

    /**
    Removes all objects except the specified object (if it exists).

    O(log(N))
    */
    public func removeAll(except element: Element) {
        let index = storage.binarySearch(element)
        storage.removeAll()
        if index >= 0 {
            storage.append(element)
        }
    }

    /**
    Removes all objects from the set.
    */
    public func removeAll() {
        storage.removeAll()
    }

    /**
    Returns the index of the object. Returns .found(index) if the object was found, or .notFound(insertionIndex),
    where the insertionIndex is the index where it should be inserted in the array for correct ordering.
    */
    public func search(_ element: Element) -> SearchResult {
        let i = storage.binarySearch(element)

        if (i >= 0) {
            return .found(index: i)
        } else {
            return .notFound(insertionIndex: -(i + 1))
        }
    }

    public func index(of element: Element) -> Index? {
        switch search(element) {
        case .found(let i):
            return i
        case .notFound:
            return nil
        }
    }

    // MARK: - Collection implementation

    public func makeIterator() -> Iterator {
        return storage.makeIterator()
    }

    public var startIndex: Index {
        return storage.startIndex
    }

    public var endIndex: Index {
        return storage.endIndex
    }

    public subscript (position: Index) -> Iterator.Element {
        return storage[position]
    }

    public func index(after i: Index) -> Index {
        return storage.index(after: i)
    }
}

private extension Array where Element: Comparable {

    /**
    Returns the index of the element if found or if not found -(insertionIndex + 1) where the insertionIndex is the index
    where the element should be inserted for correct sorting order.

    This method assumes the array is already sorted, otherwise the result is not defined.
    */
    func binarySearch(_ element: Element) -> Int {
        var low = 0
        var high = self.count - 1

        while (low <= high) {
            let mid = (low + high) >> 1
            let midVal = self[mid]

            if (midVal < element) {
                low = mid + 1
            } else if (midVal > element) {
                high = mid - 1
            } else {
                return mid
            }
        }
        return -(low + 1)
    }
}