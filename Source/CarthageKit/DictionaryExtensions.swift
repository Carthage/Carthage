import Foundation

extension Dictionary {
	/**
	Returns the value for the specified key if it exists, else it will store the default value as created by the closure and will return that value instead.

	This method is useful for caches where the first time a value is instantiated it should be stored in the cache for subsequent use.

	Compare this to the method [_ key, default: ] which does return a default but doesn't store it in the dictionary.
	*/
	mutating func object(for key: Dictionary.Key, byStoringDefault defaultValue: @autoclosure () throws -> Dictionary.Value) rethrows -> Dictionary.Value {
		if let v = self[key] {
			return v
		} else {
			let dv = try defaultValue()
			self[key] = dv
			return dv
		}
	}

	/**
	Returns a new dictionary by transforming the values of the receiver with the specified transform and removes all values for which the transform returns nil.
	*/
	func filterMapValues<T>(_ transform: (Dictionary.Value) throws -> T?) rethrows -> [Dictionary.Key: T] {
		var result = [Dictionary.Key: T]()
		for (key, value) in self {
			if let transformedValue = try transform(value) {
				result[key] = transformedValue
			}
		}

		return result
	}
}
