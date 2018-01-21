/*
This source file is part of the Swift.org open source project
Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception
See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Delta debugging algorithm (A. Zeller '99) for minimizing arbitrary sets
/// using a predicate function.
///
/// The result of the algorithm is a subset of the input change set which is
/// guaranteed to satisfy the predicate, assuming that the input set did. For
/// well formed predicates, the result set is guaranteed to be such that
/// removing any single element would falsify the predicate.
///
/// For best results the predicate function *should* (but need not) satisfy
/// certain properties, in particular:
///  (1) The predicate should return false on an empty set and true on the full
///  set.
///  (2) If the predicate returns true for a set of changes, it should return
///  true for all supersets of that set.
///
/// It is not an error to provide a predicate that does not satisfy these
/// requirements, and the algorithm will generally produce reasonable results.
/// However, it may run substantially more tests than with a good predicate.
public struct DeltaAlgorithm<Change: Hashable> {
	
	public init() {}
	
	/// Minimizes the set `changes` by executing `predicate` on subsets of
	/// changes and returning the smallest set which still satisfies the test
	/// predicate.
	public func run(changes: Set<Change>, predicate: (Set<Change>) throws -> Bool) rethrows -> Set<Change> {
		// Check empty set first to quickly find poor test functions.
		if try predicate(Set()) {
			return Set()
		}
		// Run the algorithm.
		return try delta(changes: changes, changeSets: split(changes), predicate: predicate)
	}
	
	/// Partition a set of changes into one or two subsets.
	func split(_ set: Set<Change>) -> [Set<Change>] {
		var lhs = Set<Change>()
		var rhs = Set<Change>()
		let n = set.count / 2
		for (idx, element) in set.enumerated() {
			if idx < n {
				lhs.insert(element)
			} else {
				rhs.insert(element)
			}
		}
		var result = [Set<Change>]()
		if !lhs.isEmpty {
			result.append(lhs)
		}
		if !rhs.isEmpty {
			result.append(rhs)
		}
		return result
	}
	
	/// Minimizes a set of `changes` which has been partioned into smaller sets,
	/// by attempting to remove individual subsets.
	func delta(
		changes: Set<Change>,
		changeSets: [Set<Change>],
		predicate: (Set<Change>) throws -> Bool
		) rethrows -> Set<Change> {
		// If there is nothing left we can remove, we are done.
		if changeSets.count <= 1 {
			return changes
		}
		
		// Look for a passing subset.
		if let result = try search(changes: changes, changeSets: changeSets, predicate: predicate) {
			return result
		}
		
		// Otherwise, partition the sets if possible; if not we are done.
		let splitSets = changeSets.flatMap(split)
		if splitSets.count == changeSets.count {
			return changes
		}
		return try delta(changes: changes, changeSets: splitSets, predicate: predicate)
	}
	
	/// Search for a subset (or subsets) in `changeSets` which can be
	/// removed from `changes` while still satisfying the predicate.
	///
	/// - Returns: a subset of `changes` which satisfies the predicate.
	func search(
		changes: Set<Change>,
		changeSets: [Set<Change>],
		predicate: (Set<Change>) throws -> Bool
		) rethrows -> Set<Change>? {
		for (idx, currentSet) in changeSets.enumerated() {
			// If the test passes on this subset alone, recurse.
			if try predicate(currentSet) {
				return try delta(
					changes: currentSet, changeSets: split(currentSet), predicate: predicate)
			}
			
			// Otherwise, if we have more than two sets, see if test passes on the complement.
			if changeSets.count > 2 {
				let compliment = changes.subtracting(currentSet)
				if try predicate(compliment) {
					var complimentSets = [Set<Change>]()
					let idxIndex = changeSets.index(changeSets.startIndex, offsetBy: idx)
					complimentSets += changeSets[changeSets.startIndex..<idxIndex]
					complimentSets += changeSets[changeSets.index(after: idxIndex)..<changeSets.endIndex]
					return try delta(
						changes: compliment,
						changeSets: complimentSets,
						predicate: predicate)
				}
			}
		}
		return nil
	}
}
