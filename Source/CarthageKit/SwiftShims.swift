#if !swift(>=4.1)
extension Sequence {
	func compactMap<ElementOfResult>(_ transform: (Self.Element) throws -> ElementOfResult?) rethrows -> [ElementOfResult] {
		return try flatMap(transform)
	}
}

func == (lhs: FrameworkType??, rhs: FrameworkType) -> Bool {
	if let unwrapOne = lhs,
		let unwrapTwo = unwrapOne {
		return unwrapTwo == rhs
	}
	return false
}
#endif
