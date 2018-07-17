import Foundation
import MachO.loader
import ReactiveTask
import ReactiveSwift
import Result

/// Represents a Mach header
///
/// Provides a unified structure for
/// `MachO.loader.mach_header` and `MachO.loader.mach_header_64`

struct MachHeader {

	enum Endianness {
		case little
		case big
	}

	let magic: UInt32
	let cpuType: cpu_type_t
	let cpuSubtype: cpu_type_t
	let fileType: UInt32
	let ncmds: UInt32
	let sizeofcmds: UInt32
	let flags: UInt32
	let reserved: UInt32?

	var is64BitHeader: Bool {

		return magic == MH_MAGIC_64 || magic == MH_CIGAM_64
	}

	var is32BitHeader: Bool {

		return !is64BitHeader
	}

	var endianess: Endianness {

		return magic == MH_CIGAM_64 || magic == MH_CIGAM ? .big : .little
	}
}

extension MachHeader {

	static let carthageSupportedFileTypes: Set<UInt32> = {
		return Set([
			MH_OBJECT, // Carthage accepts static libraries
			MH_BUNDLE, // Bundles https://github.com/ResearchKit/ResearchKit/blob/1.3.0/ResearchKit/Info.plist#L15-L16
			MH_DYLIB, // or dynamic shared libraries
			].map { UInt32($0) }
		)
	}()
}

extension MachHeader {

	/// Reads the Mach headers from a Mach-O file.
	/// - Parameter url: The url of the Mach-O file
	/// - Remark: Uses `objdump` to read the header and parse the output.
	///           The output is composed of one or more sets of lines like the following:
	///
	///           Mach header
	///                 magic  cputype cpusubtype  caps    filetype ncmds sizeofcmds      flags
	///            0xfeedfacf 16777223          3  0x00           1     8       1720 0x00002000
	///
	/// - See Also:  [LLVM MachODump.cpp](https://llvm.org/viewvc/llvm-project/llvm/trunk/tools/llvm-objdump/MachODump.cpp?view=markup&pathrev=225383###see%C2%B7line%C2%B72745)

	static func headers(forMachOFileAtUrl url: URL) -> SignalProducer<MachHeader, CarthageError> {

		// This is the command `otool -h` actually invokes
		let task = Task("/usr/bin/xcrun", arguments: [
			"objdump",
			"-macho",
			"-private-header",
			"-non-verbose",
			url.resolvingSymlinksInPath().path
			]
		)

		return task.launch(standardInput: nil)
			.ignoreTaskData()
			.map { String(data: $0, encoding: .utf8) ?? "" }
			.filter { !$0.isEmpty }
			.flatMap(.merge) { (output: String) -> SignalProducer<(String, String), NoError> in
				output.linesProducer.combinePrevious()
			}.filterMap { (previousLine, currentLine) -> MachHeader? in

				let previousLineComponents = previousLine
					.components(separatedBy: CharacterSet.whitespaces)
					.filter { !$0.isEmpty }
				let currentLineComponents = currentLine
					.components(separatedBy: CharacterSet.whitespaces)
					.filter { !$0.isEmpty }

				let strippedComponents = currentLineComponents
					.map { $0.stripping(prefix: "0x")}

				let magicIdentifiers = [
					MH_MAGIC_64,
					MH_CIGAM_64,
					MH_MAGIC,
					MH_CIGAM,
					].lazy

				guard previousLineComponents == [
					"magic",
					"cputype",
					"cpusubtype",
					"caps",
					"filetype",
					"ncmds",
					"sizeofcmds",
					"flags"
					]
					, !strippedComponents.isEmpty
					, let magic = UInt32(strippedComponents.first!, radix:16)
					, magicIdentifiers.first(where: { $0 ==  magic }) != nil else {
						return  nil
				}

				guard
					let cpuType = cpu_type_t(strippedComponents[1], radix: 10),
					let cpuSubtype =  cpu_subtype_t(strippedComponents[2], radix: 10),
					let fileType = UInt32(strippedComponents[4], radix: 10),
					let ncmds = UInt32(strippedComponents[5], radix: 10),
					let sizeofcmds = UInt32(strippedComponents[6], radix: 10),
					let flags = UInt32(strippedComponents[7], radix: 16)
					else {
						return nil
				}

				return MachHeader(
					magic: magic,
					cpuType: cpuType,
					cpuSubtype: cpuSubtype,
					fileType: fileType,
					ncmds: ncmds,
					sizeofcmds: sizeofcmds,
					flags: flags,
					reserved: nil
				)
			}
			.mapError(CarthageError.taskError)
	}
}
