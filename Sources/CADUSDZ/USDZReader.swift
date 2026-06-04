import Foundation
import CADUSD

#if CAD_ENABLE_USDC_READER
import CADUSDC
#endif

public struct USDZReader: USDSceneReader {
    public static let fileSignature: [UInt8] = [0x50, 0x4b]

    private let textReader: USDAReader

    public init(textReader: USDAReader = USDAReader()) {
        self.textReader = textReader
    }

    public func read(from data: Data) throws -> USDScene {
        guard data.starts(with: Self.fileSignature) else {
            throw USDImportError.invalidData("USDZ data is missing the ZIP signature.")
        }

        let package = try USDZPackage(data: data)
        guard let defaultLayer = package.entries.first else {
            throw USDImportError.invalidData("USDZ package contains no entries.")
        }
        guard defaultLayer.isUSDLayer else {
            throw USDImportError.unsupportedFeature("USDZ default layer must be the first file and use a USD extension.")
        }
        return try readLayer(defaultLayer)
    }

    private func readLayer(_ entry: USDZEntry) throws -> USDScene {
        switch entry.fileExtension {
        case "usda":
            return try textReader.read(from: entry.data)
        case "usd":
            if entry.data.starts(with: USDCReaderSignature.bytes) {
                return try readUSDC(entry.data)
            }
            return try textReader.read(from: entry.data)
        case "usdc":
            return try readUSDC(entry.data)
        default:
            throw USDImportError.unsupportedFeature("USDZ default layer \(entry.path) is not a USD layer.")
        }
    }

    private func readUSDC(_ data: Data) throws -> USDScene {
        #if CAD_ENABLE_USDC_READER
        return try USDCReader().read(from: data)
        #else
        throw USDImportError.unsupportedFeature("USDC default layers in USDZ require the USDCImport trait.")
        #endif
    }
}

private enum USDCReaderSignature {
    static let bytes = Data("PXR-USDC".utf8)
}

private struct USDZPackage {
    var entries: [USDZEntry]

    init(data: Data) throws {
        let reader = USDZBinaryReader(data: data)
        let endRecord = try reader.readEndOfCentralDirectory()
        entries = try reader.readLocalEntries(until: endRecord.centralDirectoryOffset)
        try reader.validateCentralDirectory(endRecord: endRecord, localEntries: entries)
    }
}

private struct USDZEntry: Sendable, Equatable {
    var path: String
    var data: Data
    var localHeaderOffset: Int
    var dataOffset: Int
    var crc32: UInt32

    var fileExtension: String {
        guard let lastComponent = path.split(separator: "/").last,
              let extensionStart = lastComponent.lastIndex(of: ".") else {
            return ""
        }
        return String(lastComponent[lastComponent.index(after: extensionStart)...]).lowercased()
    }

    var isUSDLayer: Bool {
        switch fileExtension {
        case "usd", "usda", "usdc":
            true
        default:
            false
        }
    }
}

private struct USDZEndOfCentralDirectory {
    var entryCount: Int
    var centralDirectoryOffset: Int
    var centralDirectorySize: Int
    var endOffset: Int
}

private struct USDZBinaryReader {
    let data: Data

    func readEndOfCentralDirectory() throws -> USDZEndOfCentralDirectory {
        let minimumByteCount = 22
        guard data.count >= minimumByteCount else {
            throw USDImportError.invalidData("USDZ package is missing the end of central directory.")
        }
        let lowerBound = max(0, data.count - minimumByteCount - 65_535)
        var offset = data.count - minimumByteCount
        while offset >= lowerBound {
            if try readUInt32(at: offset) == 0x06054b50 {
                let commentLength = Int(try readUInt16(at: offset + 20))
                if offset + minimumByteCount + commentLength == data.count {
                    return try parseEndOfCentralDirectory(at: offset, commentLength: commentLength)
                }
            }
            offset -= 1
        }
        throw USDImportError.invalidData("USDZ package is missing the end of central directory.")
    }

    func readLocalEntries(until centralDirectoryOffset: Int) throws -> [USDZEntry] {
        var entries: [USDZEntry] = []
        var seenPaths: Set<String> = []
        var offset = 0
        while offset < centralDirectoryOffset {
            let entry = try readLocalEntry(at: offset, centralDirectoryOffset: centralDirectoryOffset)
            guard seenPaths.insert(entry.path).inserted else {
                throw USDImportError.invalidData("USDZ package contains a duplicate entry \(entry.path).")
            }
            entries.append(entry)
            offset = entry.dataOffset + entry.data.count
        }
        guard offset == centralDirectoryOffset else {
            throw USDImportError.invalidData("USDZ local entries do not end at the central directory.")
        }
        return entries
    }

    func validateCentralDirectory(endRecord: USDZEndOfCentralDirectory, localEntries: [USDZEntry]) throws {
        guard endRecord.entryCount == localEntries.count else {
            throw USDImportError.invalidData("USDZ central directory entry count does not match local entries.")
        }
        let expectedEnd = endRecord.centralDirectoryOffset + endRecord.centralDirectorySize
        guard expectedEnd == endRecord.endOffset else {
            throw USDImportError.invalidData("USDZ central directory size does not match the end record.")
        }
        var offset = endRecord.centralDirectoryOffset
        for localEntry in localEntries {
            guard try readUInt32(at: offset) == 0x02014b50 else {
                throw USDImportError.invalidData("USDZ central directory is malformed.")
            }
            let flags = try readUInt16(at: offset + 8)
            try validateGeneralPurposeFlags(flags, path: localEntry.path)
            let method = try readUInt16(at: offset + 10)
            guard method == 0 else {
                throw USDImportError.unsupportedFeature("USDZ entry \(localEntry.path) is compressed.")
            }
            let crc32 = try readUInt32(at: offset + 16)
            let compressedSize = try checkedInt(try readUInt32(at: offset + 20), label: "USDZ compressed size")
            let uncompressedSize = try checkedInt(try readUInt32(at: offset + 24), label: "USDZ uncompressed size")
            guard compressedSize == uncompressedSize,
                  compressedSize == localEntry.data.count,
                  crc32 == localEntry.crc32 else {
                throw USDImportError.invalidData("USDZ central directory does not match local entry \(localEntry.path).")
            }
            let nameLength = Int(try readUInt16(at: offset + 28))
            let extraLength = Int(try readUInt16(at: offset + 30))
            let commentLength = Int(try readUInt16(at: offset + 32))
            let localHeaderOffset = try checkedInt(try readUInt32(at: offset + 42), label: "USDZ local header offset")
            let nameStart = offset + 46
            let nameEnd = try checkedOffset(nameStart, adding: nameLength)
            let recordEnd = try checkedOffset(try checkedOffset(nameEnd, adding: extraLength), adding: commentLength)
            guard recordEnd <= endRecord.endOffset else {
                throw USDImportError.invalidData("USDZ central directory record is truncated.")
            }
            let path = try readUTF8String(in: nameStart..<nameEnd)
            guard path == localEntry.path,
                  localHeaderOffset == localEntry.localHeaderOffset else {
                throw USDImportError.invalidData("USDZ central directory order does not match local entries.")
            }
            offset = recordEnd
        }
        guard offset == endRecord.endOffset else {
            throw USDImportError.invalidData("USDZ central directory has trailing bytes.")
        }
    }

    private func parseEndOfCentralDirectory(at offset: Int, commentLength: Int) throws -> USDZEndOfCentralDirectory {
        let diskNumber = try readUInt16(at: offset + 4)
        let centralDirectoryDisk = try readUInt16(at: offset + 6)
        let diskEntryCount = try readUInt16(at: offset + 8)
        let entryCount = try readUInt16(at: offset + 10)
        guard diskNumber == 0,
              centralDirectoryDisk == 0,
              diskEntryCount == entryCount,
              commentLength == 0 else {
            throw USDImportError.unsupportedFeature("USDZ package uses unsupported ZIP disk or comment fields.")
        }
        let centralDirectorySize = try checkedInt(try readUInt32(at: offset + 12), label: "USDZ central directory size")
        let centralDirectoryOffset = try checkedInt(try readUInt32(at: offset + 16), label: "USDZ central directory offset")
        guard centralDirectoryOffset <= data.count,
              centralDirectorySize <= data.count - centralDirectoryOffset,
              centralDirectoryOffset + centralDirectorySize == offset else {
            throw USDImportError.invalidData("USDZ central directory range is invalid.")
        }
        return USDZEndOfCentralDirectory(
            entryCount: Int(entryCount),
            centralDirectoryOffset: centralDirectoryOffset,
            centralDirectorySize: centralDirectorySize,
            endOffset: offset
        )
    }

    private func readLocalEntry(at offset: Int, centralDirectoryOffset: Int) throws -> USDZEntry {
        guard try readUInt32(at: offset) == 0x04034b50 else {
            throw USDImportError.invalidData("USDZ local entry is missing a ZIP local header.")
        }
        let flags = try readUInt16(at: offset + 6)
        let method = try readUInt16(at: offset + 8)
        let crc32 = try readUInt32(at: offset + 14)
        let compressedSize = try checkedInt(try readUInt32(at: offset + 18), label: "USDZ compressed size")
        let uncompressedSize = try checkedInt(try readUInt32(at: offset + 22), label: "USDZ uncompressed size")
        let nameLength = Int(try readUInt16(at: offset + 26))
        let extraLength = Int(try readUInt16(at: offset + 28))
        try validateGeneralPurposeFlags(flags, path: "local entry at \(offset)")
        guard method == 0 else {
            throw USDImportError.unsupportedFeature("USDZ local entry at \(offset) is compressed.")
        }
        guard compressedSize == uncompressedSize else {
            throw USDImportError.invalidData("USDZ local entry at \(offset) has mismatched stored sizes.")
        }
        let nameStart = offset + 30
        let nameEnd = try checkedOffset(nameStart, adding: nameLength)
        let dataOffset = try checkedOffset(nameEnd, adding: extraLength)
        let dataEnd = try checkedOffset(dataOffset, adding: compressedSize)
        guard dataEnd <= centralDirectoryOffset else {
            throw USDImportError.invalidData("USDZ local entry at \(offset) overlaps the central directory.")
        }
        guard dataOffset.isMultiple(of: 64) else {
            throw USDImportError.invalidData("USDZ local entry payload is not 64-byte aligned.")
        }
        let path = try readUTF8String(in: nameStart..<nameEnd)
        try validateEntryPath(path)
        let payload = try readData(in: dataOffset..<dataEnd)
        guard USDZCRC32.checksum(payload) == crc32 else {
            throw USDImportError.invalidData("USDZ local entry \(path) has a CRC mismatch.")
        }
        return USDZEntry(path: path, data: payload, localHeaderOffset: offset, dataOffset: dataOffset, crc32: crc32)
    }

    private func validateGeneralPurposeFlags(_ flags: UInt16, path: String) throws {
        let encrypted = UInt16(1) << 0
        let dataDescriptor = UInt16(1) << 3
        guard flags & encrypted == 0 else {
            throw USDImportError.unsupportedFeature("USDZ entry \(path) is encrypted.")
        }
        guard flags & dataDescriptor == 0 else {
            throw USDImportError.unsupportedFeature("USDZ entry \(path) uses a data descriptor.")
        }
    }

    private func validateEntryPath(_ path: String) throws {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasSuffix("/"),
              !path.contains("\\") else {
            throw USDImportError.invalidData("USDZ entry path \(path) is invalid.")
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw USDImportError.invalidData("USDZ entry path \(path) is invalid.")
        }
    }

    private func readUInt16(at offset: Int) throws -> UInt16 {
        let bytes = try readBytes(at: offset, byteCount: 2)
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }

    private func readUInt32(at offset: Int) throws -> UInt32 {
        let bytes = try readBytes(at: offset, byteCount: 4)
        return UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
    }

    private func readUTF8String(in range: Range<Int>) throws -> String {
        let data = try readData(in: range)
        guard let string = String(data: data, encoding: .utf8) else {
            throw USDImportError.invalidData("USDZ entry path is not UTF-8.")
        }
        return string
    }

    private func readData(in range: Range<Int>) throws -> Data {
        guard range.lowerBound >= 0,
              range.upperBound <= data.count,
              range.lowerBound <= range.upperBound else {
            throw USDImportError.invalidData("USDZ read is outside the package.")
        }
        guard !range.isEmpty else {
            return Data()
        }
        let start = data.index(data.startIndex, offsetBy: range.lowerBound)
        let end = data.index(data.startIndex, offsetBy: range.upperBound)
        return Data(data[start..<end])
    }

    private func readBytes(at offset: Int, byteCount: Int) throws -> [UInt8] {
        guard offset >= 0,
              byteCount >= 0,
              offset <= data.count - byteCount else {
            throw USDImportError.invalidData("USDZ read is outside the package.")
        }
        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: byteCount)
        return Array(data[start..<end])
    }

    private func checkedInt(_ value: UInt32, label: String) throws -> Int {
        guard UInt64(value) <= UInt64(Int.max) else {
            throw USDImportError.invalidData("\(label) exceeds platform range.")
        }
        return Int(value)
    }

    private func checkedOffset(_ offset: Int, adding value: Int) throws -> Int {
        guard value >= 0, offset <= Int.max - value else {
            throw USDImportError.invalidData("USDZ offset exceeds platform range.")
        }
        return offset + value
    }
}

private enum USDZCRC32 {
    static let table: [UInt32] = {
        (0..<256).map { value in
            var crc = UInt32(value)
            for _ in 0..<8 {
                if crc & 1 == 1 {
                    crc = (crc >> 1) ^ 0xedb88320
                } else {
                    crc >>= 1
                }
            }
            return crc
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ 0xffff_ffff
    }
}
