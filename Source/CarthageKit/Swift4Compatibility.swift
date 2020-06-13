import Foundation

#if compiler(>=5)
/// Aliased to provide source-compatibility when building Carthage using Swift 4.2.
/// Prior to Swift 5, Carthage and its dependencies used
///
///     SignalProducer<U, Result.NoError>
///
/// to represent a producer that could never send an error. In Swift 5, this changed to
///
///     SignalProducer<U, Swift.Never>
typealias NoError = Never
#endif
