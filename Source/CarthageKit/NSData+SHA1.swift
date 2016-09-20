//
//  NSData+SHA1.swift
//  SHA1 extensions for NSData from CryptoSwift by Marcin Krzyżanowski
//  https://github.com/krzyzanowskim/CryptoSwift/
//
//  Created by Jason Boyle on 9/15/16.
//

//
//  Copyright (C) 2014 Marcin Krzyżanowski <marcin.krzyzanowski@gmail.com>
//  This software is provided 'as-is', without any express or implied warranty.
//
//  In no event will the authors be held liable for any damages arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:
//
//  - The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation is required.
//  - Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
//  - This notice may not be removed or altered from any source or binary distribution.
//

public extension NSData {
	func sha1() -> NSData? {
		let result = SHA1(arrayOfBytes()).calculate()
		return NSData.withBytes(result)
	}
	
	func toHexString() -> String {
		return arrayOfBytes().toHexString()
	}
}

private struct BytesSequence: SequenceType {
	let chunkSize: Int
	let data: Array<UInt8>
	
	func generate() -> AnyGenerator<ArraySlice<UInt8>> {
		
		var offset: Int = 0
		
		return AnyGenerator {
			let end = min(self.chunkSize, self.data.count - offset)
			let result = self.data[offset..<offset + end]
			offset += result.count
			return !result.isEmpty ? result : nil
		}
	}
}

private final class SHA1 {
	static let size: Int = 20 // 160 / 8
	let message: Array<UInt8>
	
	init(_ message: Array<UInt8>) {
		self.message = message
	}
	
	private let h: Array<UInt32> = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]
	
	func calculate() -> Array<UInt8> {
		var tmpMessage = prepare(64)
		
		// hash values
		var hh = h
		
		// append message length, in a 64-bit big-endian integer. So now the message length is a multiple of 512 bits.
		tmpMessage += (message.count * 8).bytes(64 / 8)
		
		// Process the message in successive 512-bit chunks:
		let chunkSizeBytes = 512 / 8 // 64
		for chunk in BytesSequence(chunkSize: chunkSizeBytes, data: tmpMessage) {
			// break chunk into sixteen 32-bit words M[j], 0 ≤ j ≤ 15, big-endian
			// Extend the sixteen 32-bit words into eighty 32-bit words:
			var M: Array<UInt32> = Array<UInt32>(count: 80, repeatedValue: 0)
			for x in 0..<M.count {
				switch (x) {
				case 0...15:
					let start = chunk.startIndex + (x * sizeofValue(M[x]))
					let end = start + sizeofValue(M[x])
					let le = toUInt32Array(chunk[start..<end])[0]
					M[x] = le.bigEndian
					break
				default:
					M[x] = rotateLeft(M[x-3] ^ M[x-8] ^ M[x-14] ^ M[x-16], 1) //FIXME: n:
					break
				}
			}
			
			var A = hh[0]
			var B = hh[1]
			var C = hh[2]
			var D = hh[3]
			var E = hh[4]
			
			// Main loop
			for j in 0...79 {
				var f: UInt32 = 0;
				var k: UInt32 = 0
				
				switch (j) {
				case 0...19:
					f = (B & C) | ((~B) & D)
					k = 0x5A827999
					break
				case 20...39:
					f = B ^ C ^ D
					k = 0x6ED9EBA1
					break
				case 40...59:
					f = (B & C) | (B & D) | (C & D)
					k = 0x8F1BBCDC
					break
				case 60...79:
					f = B ^ C ^ D
					k = 0xCA62C1D6
					break
				default:
					break
				}
				
				let temp = (rotateLeft(A,5) &+ f &+ E &+ M[j] &+ k) & 0xffffffff
				E = D
				D = C
				C = rotateLeft(B, 30)
				B = A
				A = temp
			}
			
			hh[0] = (hh[0] &+ A) & 0xffffffff
			hh[1] = (hh[1] &+ B) & 0xffffffff
			hh[2] = (hh[2] &+ C) & 0xffffffff
			hh[3] = (hh[3] &+ D) & 0xffffffff
			hh[4] = (hh[4] &+ E) & 0xffffffff
		}
		
		// Produce the final hash value (big-endian) as a 160 bit number:
		var result = Array<UInt8>()
		result.reserveCapacity(hh.count / 4)
		hh.forEach {
			let item = $0.bigEndian
			result += [UInt8(item & 0xff), UInt8((item >> 8) & 0xff), UInt8((item >> 16) & 0xff), UInt8((item >> 24) & 0xff)]
		}
		return result
	}
	
	func prepare(len: Int) -> Array<UInt8> {
		var tmpMessage = message
		
		// Step 1. Append Padding Bits
		tmpMessage.append(0x80) // append one bit (UInt8 with one bit) to message
		
		// append "0" bit until message length in bits ≡ 448 (mod 512)
		var msgLength = tmpMessage.count
		var counter = 0
		
		while msgLength % len != (len - 8) {
			counter += 1
			msgLength += 1
		}
		
		tmpMessage += Array<UInt8>(count: counter, repeatedValue: 0)
		return tmpMessage
	}
}

private func rotateLeft(v: UInt32, _ n: UInt32) -> UInt32 {
	return ((v << n) & 0xFFFFFFFF) | (v >> (32 - n))
}

private func toUInt32Array(slice: ArraySlice<UInt8>) -> Array<UInt32> {
	var result = Array<UInt32>()
	result.reserveCapacity(16)
	
	for idx in slice.startIndex.stride(to: slice.endIndex, by: sizeof(UInt32)) {
		let val1: UInt32 = (UInt32(slice[idx.advancedBy(3)]) << 24)
		let val2: UInt32 = (UInt32(slice[idx.advancedBy(2)]) << 16)
		let val3: UInt32 = (UInt32(slice[idx.advancedBy(1)]) << 8)
		let val4: UInt32 = UInt32(slice[idx])
		let val: UInt32 = val1 | val2 | val3 | val4
		result.append(val)
	}
	return result
}

/// Array of bytes, little-endian representation. Don't use if not necessary.
/// I found this method slow
private func arrayOfBytes<T>(value: T, length: Int? = nil) -> Array<UInt8> {
	let totalBytes = length ?? sizeof(T)
	
	let valuePointer = UnsafeMutablePointer<T>.alloc(1)
	valuePointer.memory = value
	
	let bytesPointer = UnsafeMutablePointer<UInt8>(valuePointer)
	var bytes = Array<UInt8>(count: totalBytes, repeatedValue: 0)
	for j in 0..<min(sizeof(T),totalBytes) {
		bytes[totalBytes - 1 - j] = (bytesPointer + j).memory
	}
	
	valuePointer.destroy()
	valuePointer.dealloc(1)
	
	return bytes
}

/* array of bytes */
private extension Int {
	/** Array of bytes with optional padding (little-endian) */
	func bytes(totalBytes: Int = sizeof(Int)) -> Array<UInt8> {
		return arrayOfBytes(self, length: totalBytes)
	}
}

private extension NSData {
	private func arrayOfBytes() -> Array<UInt8> {
		let count = length / sizeof(UInt8)
		var bytesArray = Array<UInt8>(count: count, repeatedValue: 0)
		getBytes(&bytesArray, length: count * sizeof(UInt8))
		return bytesArray
	}
	
	private class func withBytes(bytes: Array<UInt8>) -> NSData {
		return NSData(bytes: bytes, length: bytes.count)
	}
}

private extension _ArrayType where Generator.Element == UInt8 {
	func toHexString() -> String {
		return lazy.reduce("") { $0 + String(format: "%02x", $1) }
	}
}
