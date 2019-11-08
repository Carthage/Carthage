import Foundation
import CommonCrypto
import ReactiveSwift

class SHA256Hasher {

	enum HasherError: Error, CustomStringConvertible {

		case finalized

		var description: String {

			switch self{
			case .finalized:
				return "Cannot use a hasher that has been already finalized. Reset the hasher first."
			}
		}
	}

	private var sha256Context = CC_SHA256_CTX()
	private var mutex = pthread_mutex_t()
	private var finalized = false

	deinit {
		pthread_mutex_destroy(&mutex)
	}

	init() {

		var attr = pthread_mutexattr_t()
		guard pthread_mutexattr_init(&attr) == 0 else {
			preconditionFailure("Could not create mutex attributes")
		}

		pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE)
		guard pthread_mutex_init(&mutex, &attr) == 0 else {
			preconditionFailure("Could not create mutex")
		}
		pthread_mutexattr_destroy(&attr)

		CC_SHA256_Init(&sha256Context)
	}

	func hash(_ data: Data) throws {
		pthread_mutex_lock(&mutex)

		guard !finalized else {
			pthread_mutex_unlock(&mutex)
			throw HasherError.finalized
		}

		_ = data.withUnsafeBytes { ptr in
			CC_SHA256_Update(&sha256Context, ptr, CC_LONG(data.count))
		}
		pthread_mutex_unlock(&mutex)
	}

	func finalize() throws -> String {
		pthread_mutex_lock(&mutex)
		guard !finalized else {
			pthread_mutex_unlock(&mutex)
			throw HasherError.finalized
		}

		let sha56hash = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(CC_SHA256_DIGEST_LENGTH))
		// https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/CC_SHA256.3cc.html
		// CC_SHA256_Final() places the message digest in md, which must have space
		// for CC_SHA256_DIGEST_LENGTH == 20 bytes of output, and __erases the
		// CC_SHA256_CTX__.
		CC_SHA256_Final(sha56hash, &sha256Context)
		finalized = true
		let data = Data(bytes: sha56hash, count: Int(CC_SHA256_DIGEST_LENGTH))
		let stringRep = data.reduce("") {$0 + String(format: "%02hhx", $1)}
		sha56hash.deallocate()

		pthread_mutex_unlock(&mutex)

		return stringRep
	}

	func reset() {
		pthread_mutex_lock(&mutex)

		CC_SHA256_Init(&sha256Context)
		finalized = false

		pthread_mutex_unlock(&mutex)
	}
}

extension SHA256Hasher {

	func finalizeProducer() -> SignalProducer<String, CarthageError> {

		do {
			let sum: String = try self.finalize()
			return SignalProducer(value: sum)
		}
		catch let error {

			let description = (error as? SHA256Hasher.HasherError)?.description ?? "Unknown Error"
			return SignalProducer(error: CarthageError.internalError(description: description))
		}
	}
}

