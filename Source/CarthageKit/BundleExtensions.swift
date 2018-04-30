import Foundation

extension Bundle {
	var packageType: PackageType? {
		return (self.object(forInfoDictionaryKey: "CFBundlePackageType") as? String)
			.flatMap { PackageType(rawValue: $0) }
	}
}
