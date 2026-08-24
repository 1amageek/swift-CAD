import Foundation
import CADCore

public enum ZipArchiveError: Error, Equatable, Sendable {
    case tooManyEntries
    case entryTooLarge(String)
    case duplicateEntry(String)
    case invalidEntryPath(String)
    case entryPayloadMismatch(String)
    case invalidCompressedData(String)
    case unsupportedCompressionMethod(UInt16)
    case invalidCentralDirectory
    case localHeaderMismatch(String)
    case missingEndOfCentralDirectory
    case truncatedArchive
    case crcMismatch(String)
}

public struct StoredZipArchive {
    public struct Entry: Sendable {
        public var path: String
        public var data: Data

        public init(path: String, data: Data) {
            self.path = path
            self.data = data
        }
    }

    struct StreamedEntry {
        var path: String
        var byteCount: Int
        var crc: UInt32
        var write: (any ByteSink) throws -> Void
    }

    public static func make(entries: [Entry]) throws -> Data {
        let sink = DataByteSink()
        try write(entries: entries, to: sink)
        return sink.bytes
    }

    public static func write(entries: [Entry], to sink: any ByteSink) throws {
        try write(streamedEntries: entries.map { entry in
            StreamedEntry(
                path: entry.path,
                byteCount: entry.data.count,
                crc: CRC32.checksum(entry.data),
                write: { sink in try sink.write(entry.data) }
            )
        }, to: sink)
    }

    static func write(streamedEntries entries: [StreamedEntry], to sink: any ByteSink) throws {
        guard entries.count <= Int(UInt16.max) else {
            throw ZipArchiveError.tooManyEntries
        }

        var centralDirectory = Data()
        var outputByteCount = 0
        var seenPaths: Set<String> = []

        for entry in entries {
            try validateEntryPath(entry.path)
            guard seenPaths.insert(entry.path).inserted else {
                throw ZipArchiveError.duplicateEntry(entry.path)
            }
            guard entry.byteCount >= 0,
                  UInt64(entry.byteCount) <= UInt64(UInt32.max) else {
                throw ZipArchiveError.entryTooLarge(entry.path)
            }
            let nameData = Data(entry.path.utf8)
            guard nameData.count <= Int(UInt16.max) else {
                throw ZipArchiveError.entryTooLarge(entry.path)
            }
            guard UInt64(outputByteCount) <= UInt64(UInt32.max) else {
                throw ZipArchiveError.entryTooLarge(entry.path)
            }
            let localOffset = UInt32(outputByteCount)
            let size = UInt32(entry.byteCount)

            var localHeader = Data()
            localHeader.appendLittleEndian(UInt32(0x04034b50))
            localHeader.appendLittleEndian(UInt16(20))
            localHeader.appendLittleEndian(UInt16(0))
            localHeader.appendLittleEndian(UInt16(0))
            localHeader.appendLittleEndian(UInt16(0))
            localHeader.appendLittleEndian(UInt16(0))
            localHeader.appendLittleEndian(entry.crc)
            localHeader.appendLittleEndian(size)
            localHeader.appendLittleEndian(size)
            localHeader.appendLittleEndian(UInt16(nameData.count))
            localHeader.appendLittleEndian(UInt16(0))
            try sink.write(localHeader)
            try sink.write(nameData)
            let countingSink = CountingCRCByteSink(downstream: sink)
            try entry.write(countingSink)
            guard countingSink.byteCount == entry.byteCount,
                  countingSink.crc == entry.crc else {
                throw ZipArchiveError.entryPayloadMismatch(entry.path)
            }
            outputByteCount += localHeader.count + nameData.count + entry.byteCount

            centralDirectory.appendLittleEndian(UInt32(0x02014b50))
            centralDirectory.appendLittleEndian(UInt16(20))
            centralDirectory.appendLittleEndian(UInt16(20))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(entry.crc)
            centralDirectory.appendLittleEndian(size)
            centralDirectory.appendLittleEndian(size)
            centralDirectory.appendLittleEndian(UInt16(nameData.count))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt32(0))
            centralDirectory.appendLittleEndian(localOffset)
            centralDirectory.append(nameData)
        }

        guard UInt64(outputByteCount) <= UInt64(UInt32.max),
              UInt64(centralDirectory.count) <= UInt64(UInt32.max) else {
            throw ZipArchiveError.entryTooLarge("archive")
        }
        let centralOffset = UInt32(outputByteCount)
        let centralSize = UInt32(centralDirectory.count)
        var endRecord = Data()
        endRecord.appendLittleEndian(UInt32(0x06054b50))
        endRecord.appendLittleEndian(UInt16(0))
        endRecord.appendLittleEndian(UInt16(0))
        endRecord.appendLittleEndian(UInt16(entries.count))
        endRecord.appendLittleEndian(UInt16(entries.count))
        endRecord.appendLittleEndian(centralSize)
        endRecord.appendLittleEndian(centralOffset)
        endRecord.appendLittleEndian(UInt16(0))
        try sink.write(centralDirectory)
        try sink.write(endRecord)
    }

    public static func withEntries<Result>(
        from source: any ByteSource,
        _ body: ([String: Data]) throws -> Result
    ) throws -> Result {
        let entries = try source.withUnsafeBytes { bytes in
            try ownedEntries(from: readEntries(from: bytes))
        }
        return try body(entries)
    }

    static func withBorrowedEntries<Result>(
        from source: any ByteSource,
        maximumEntryCount: Int = Int(UInt16.max),
        maximumTotalUncompressedBytes: Int = Int(UInt32.max),
        _ body: ([String: Data]) throws -> Result
    ) throws -> Result {
        try source.withUnsafeBytes { bytes in
            let entries = try readEntries(
                from: bytes,
                maximumEntryCount: maximumEntryCount,
                maximumTotalUncompressedBytes: maximumTotalUncompressedBytes
            )
            return try body(entries)
        }
    }

    public static func readEntries(from data: Data) throws -> [String: Data] {
        try data.withUnsafeBytes { bytes in
            try ownedEntries(from: readEntries(from: bytes))
        }
    }

    private static func readEntries(from bytes: UnsafeRawBufferPointer) throws -> [String: Data] {
        try readEntries(
            from: bytes,
            maximumEntryCount: Int(UInt16.max),
            maximumTotalUncompressedBytes: Int(UInt32.max)
        )
    }

    private static func readEntries(
        from bytes: UnsafeRawBufferPointer,
        maximumEntryCount: Int,
        maximumTotalUncompressedBytes: Int
    ) throws -> [String: Data] {
        guard maximumEntryCount > 0, maximumTotalUncompressedBytes > 0 else {
            throw ZipArchiveError.entryTooLarge("archive")
        }
        let endOffset = try findEndOfCentralDirectory(in: bytes)
        let diskNumber = try bytes.littleEndianUInt16(at: endOffset + 4)
        let centralDirectoryDisk = try bytes.littleEndianUInt16(at: endOffset + 6)
        let diskEntryCount = Int(try bytes.littleEndianUInt16(at: endOffset + 8))
        let entryCount = Int(try bytes.littleEndianUInt16(at: endOffset + 10))
        let centralDirectorySize32 = try bytes.littleEndianUInt32(at: endOffset + 12)
        let centralDirectoryOffset32 = try bytes.littleEndianUInt32(at: endOffset + 16)
        let commentLength = Int(try bytes.littleEndianUInt16(at: endOffset + 20))
        guard entryCount <= maximumEntryCount else {
            throw ZipArchiveError.tooManyEntries
        }
        let centralDirectoryEnd64 = UInt64(centralDirectoryOffset32) + UInt64(centralDirectorySize32)
        guard centralDirectoryEnd64 <= UInt64(Int.max) else {
            throw ZipArchiveError.invalidCentralDirectory
        }
        let centralDirectoryOffset = try checkedInt(centralDirectoryOffset32)
        let centralDirectoryEnd = Int(centralDirectoryEnd64)
        let archiveEnd = try checkedOffset(try checkedOffset(endOffset, adding: 22), adding: commentLength)
        guard diskNumber == 0,
              centralDirectoryDisk == 0,
              diskEntryCount == entryCount,
              commentLength == 0,
              centralDirectoryEnd == endOffset,
              archiveEnd == bytes.count else {
            throw ZipArchiveError.invalidCentralDirectory
        }
        var offset = centralDirectoryOffset
        var entries: [String: Data] = [:]
        var seenPaths: Set<String> = []
        var localRanges: [Range<Int>] = []
        var totalUncompressedBytes = 0

        for _ in 0..<entryCount {
            let nameStart = try checkedOffset(offset, adding: 46)
            guard nameStart <= centralDirectoryEnd else {
                throw ZipArchiveError.truncatedArchive
            }
            guard try bytes.littleEndianUInt32(at: offset) == 0x02014b50 else {
                throw ZipArchiveError.invalidCentralDirectory
            }
            let flags = try bytes.littleEndianUInt16(at: offset + 8)
            guard flags & ~supportedZipGeneralPurposeFlags == 0 else {
                throw ZipArchiveError.invalidCentralDirectory
            }
            let method = try bytes.littleEndianUInt16(at: offset + 10)
            guard method == 0 || method == 8 else {
                throw ZipArchiveError.unsupportedCompressionMethod(method)
            }
            let expectedCRC = try bytes.littleEndianUInt32(at: offset + 16)
            let compressedSize32 = try bytes.littleEndianUInt32(at: offset + 20)
            let uncompressedSize32 = try bytes.littleEndianUInt32(at: offset + 24)
            guard compressedSize32 != UInt32.max,
                  uncompressedSize32 != UInt32.max else {
                throw ZipArchiveError.entryTooLarge("ZIP64")
            }
            let compressedSize = try checkedInt(compressedSize32)
            let uncompressedSize = try checkedInt(uncompressedSize32)
            guard method != 0 || compressedSize == uncompressedSize else {
                throw ZipArchiveError.invalidCentralDirectory
            }
            guard uncompressedSize <= maximumTotalUncompressedBytes - totalUncompressedBytes else {
                throw ZipArchiveError.entryTooLarge("archive")
            }
            totalUncompressedBytes += uncompressedSize
            let fileNameLength = Int(try bytes.littleEndianUInt16(at: offset + 28))
            let extraLength = Int(try bytes.littleEndianUInt16(at: offset + 30))
            let commentLength = Int(try bytes.littleEndianUInt16(at: offset + 32))
            let diskStart = try bytes.littleEndianUInt16(at: offset + 34)
            guard commentLength == 0, diskStart == 0 else {
                throw ZipArchiveError.invalidCentralDirectory
            }
            let localOffset32 = try bytes.littleEndianUInt32(at: offset + 42)
            guard localOffset32 != UInt32.max else {
                throw ZipArchiveError.entryTooLarge("ZIP64")
            }
            let localOffset = try checkedInt(localOffset32)
            let nameEnd = try checkedOffset(nameStart, adding: fileNameLength)
            let extraEnd = try checkedOffset(nameEnd, adding: extraLength)
            let nextOffset = try checkedOffset(extraEnd, adding: commentLength)
            let pathData = try bytes.noCopyData(in: nameStart..<nameEnd)
            guard nextOffset <= centralDirectoryEnd,
                  let path = String(data: pathData, encoding: .utf8) else {
                throw ZipArchiveError.truncatedArchive
            }
            try validateZipExtraFields(bytes, range: nameEnd..<extraEnd)
            try validateEntryPath(path)
            guard seenPaths.insert(path).inserted else {
                throw ZipArchiveError.duplicateEntry(path)
            }

            let localEntry = try readLocalEntry(
                path: path,
                expectedCRC: expectedCRC,
                flags: flags,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                maximumUncompressedByteCount: maximumTotalUncompressedBytes,
                localOffset: localOffset,
                bytes: bytes
            )
            entries[path] = localEntry.data
            localRanges.append(localEntry.range)
            offset = nextOffset
        }
        guard offset == centralDirectoryEnd else {
            throw ZipArchiveError.invalidCentralDirectory
        }
        try validateLocalEntryCoverage(localRanges, centralDirectoryOffset: centralDirectoryOffset)
        return entries
    }

    private struct LocalEntry {
        var data: Data
        var range: Range<Int>
    }

    private static func readLocalEntry(
        path: String,
        expectedCRC: UInt32,
        flags: UInt16,
        method: UInt16,
        compressedSize: Int,
        uncompressedSize: Int,
        maximumUncompressedByteCount: Int,
        localOffset: Int,
        bytes: UnsafeRawBufferPointer
    ) throws -> LocalEntry {
        let localHeaderEnd = try checkedOffset(localOffset, adding: 30)
        guard localHeaderEnd <= bytes.count else {
            throw ZipArchiveError.truncatedArchive
        }
        guard try bytes.littleEndianUInt32(at: localOffset) == 0x04034b50 else {
            throw ZipArchiveError.invalidCentralDirectory
        }
        let localFlags = try bytes.littleEndianUInt16(at: localOffset + 6)
        guard localFlags == flags else {
            throw ZipArchiveError.invalidCentralDirectory
        }
        let localMethod = try bytes.littleEndianUInt16(at: localOffset + 8)
        guard localMethod == method else {
            throw ZipArchiveError.localHeaderMismatch(path)
        }
        let localCRC = try bytes.littleEndianUInt32(at: localOffset + 14)
        let localCompressedSize = try checkedInt(try bytes.littleEndianUInt32(at: localOffset + 18))
        let localUncompressedSize = try checkedInt(try bytes.littleEndianUInt32(at: localOffset + 22))
        let localNameLength = Int(try bytes.littleEndianUInt16(at: localOffset + 26))
        let localExtraLength = Int(try bytes.littleEndianUInt16(at: localOffset + 28))
        let nameStart = localHeaderEnd
        let nameEnd = try checkedOffset(nameStart, adding: localNameLength)
        let dataStart = try checkedOffset(nameEnd, adding: localExtraLength)
        let dataEnd = try checkedOffset(dataStart, adding: compressedSize)
        let localPathData = try bytes.noCopyData(in: nameStart..<nameEnd)
        guard nameEnd <= bytes.count,
              dataEnd <= bytes.count,
              let localPath = String(data: localPathData, encoding: .utf8) else {
            throw ZipArchiveError.truncatedArchive
        }
        try validateZipExtraFields(bytes, range: nameEnd..<dataStart)
        try validateEntryPath(localPath)
        guard localPath == path else {
            throw ZipArchiveError.localHeaderMismatch(path)
        }
        let usesDataDescriptor = flags & zipDataDescriptorFlag != 0
        if usesDataDescriptor {
            guard (localCRC == 0 || localCRC == expectedCRC),
                  (localCompressedSize == 0 || localCompressedSize == compressedSize),
                  (localUncompressedSize == 0 || localUncompressedSize == uncompressedSize) else {
                throw ZipArchiveError.localHeaderMismatch(path)
            }
        } else {
            guard localCRC == expectedCRC,
                  localCompressedSize == compressedSize,
                  localUncompressedSize == uncompressedSize else {
                throw ZipArchiveError.localHeaderMismatch(path)
            }
        }

        let entryData: Data
        if method == 0 {
            entryData = try bytes.noCopyData(in: dataStart..<dataEnd)
        } else {
            let compressedBytes = UnsafeRawBufferPointer(rebasing: bytes[dataStart..<dataEnd])
            do {
                entryData = try RawDeflateDecoder.decode(
                    compressedBytes,
                    expectedByteCount: uncompressedSize,
                    maximumByteCount: maximumUncompressedByteCount
                )
            } catch RawDeflateError.outputLimitExceeded {
                throw ZipArchiveError.entryTooLarge(path)
            } catch {
                throw ZipArchiveError.invalidCompressedData(path)
            }
        }
        guard CRC32.checksum(entryData) == expectedCRC else {
            throw ZipArchiveError.crcMismatch(path)
        }
        let entryEnd = usesDataDescriptor
            ? try validateDataDescriptor(
                at: dataEnd,
                expectedCRC: expectedCRC,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                bytes: bytes
            )
            : dataEnd
        return LocalEntry(data: entryData, range: localOffset..<entryEnd)
    }

    private static func validateDataDescriptor(
        at offset: Int,
        expectedCRC: UInt32,
        compressedSize: Int,
        uncompressedSize: Int,
        bytes: UnsafeRawBufferPointer
    ) throws -> Int {
        var valueOffset = offset
        if try bytes.littleEndianUInt32(at: valueOffset) == zipDataDescriptorSignature {
            valueOffset = try checkedOffset(valueOffset, adding: 4)
        }
        let descriptorEnd = try checkedOffset(valueOffset, adding: 12)
        guard descriptorEnd <= bytes.count,
              try bytes.littleEndianUInt32(at: valueOffset) == expectedCRC,
              try checkedInt(try bytes.littleEndianUInt32(at: valueOffset + 4)) == compressedSize,
              try checkedInt(try bytes.littleEndianUInt32(at: valueOffset + 8)) == uncompressedSize else {
            throw ZipArchiveError.invalidCentralDirectory
        }
        return descriptorEnd
    }

    private static func validateLocalEntryCoverage(
        _ ranges: [Range<Int>],
        centralDirectoryOffset: Int
    ) throws {
        var expectedLowerBound = 0
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            guard range.lowerBound == expectedLowerBound,
                  range.upperBound <= centralDirectoryOffset else {
                throw ZipArchiveError.invalidCentralDirectory
            }
            expectedLowerBound = range.upperBound
        }
        guard expectedLowerBound == centralDirectoryOffset else {
            throw ZipArchiveError.invalidCentralDirectory
        }
    }

    private static func findEndOfCentralDirectory(in bytes: UnsafeRawBufferPointer) throws -> Int {
        let signature: UInt32 = 0x06054b50
        guard bytes.count >= 22 else {
            throw ZipArchiveError.missingEndOfCentralDirectory
        }
        let lowerBound = max(0, bytes.count - 22 - 65535)
        var offset = bytes.count - 22
        while offset >= lowerBound {
            if try bytes.littleEndianUInt32(at: offset) == signature {
                let commentLength = Int(try bytes.littleEndianUInt16(at: offset + 20))
                if UInt64(offset) + UInt64(22) + UInt64(commentLength) == UInt64(bytes.count) {
                    return offset
                }
            }
            offset -= 1
        }
        throw ZipArchiveError.missingEndOfCentralDirectory
    }

    private static func checkedInt(_ value: UInt32) throws -> Int {
        guard UInt64(value) <= UInt64(Int.max) else {
            throw ZipArchiveError.invalidCentralDirectory
        }
        return Int(value)
    }

    private static func checkedOffset(_ offset: Int, adding value: Int) throws -> Int {
        guard value >= 0, offset <= Int.max - value else {
            throw ZipArchiveError.truncatedArchive
        }
        return offset + value
    }

    private static func ownedEntries(from entries: [String: Data]) -> [String: Data] {
        Dictionary(uniqueKeysWithValues: entries.map { path, data in
            let ownedData = data.withUnsafeBytes { bytes in
                Data(bytes)
            }
            return (path, ownedData)
        })
    }
}

private final class CountingCRCByteSink: ByteSink {
    private let downstream: any ByteSink
    private var checksum = CRC32()
    private(set) var byteCount = 0

    init(downstream: any ByteSink) {
        self.downstream = downstream
    }

    var crc: UInt32 {
        checksum.finalize()
    }

    func write(_ bytes: UnsafeRawBufferPointer) throws {
        byteCount += bytes.count
        checksum.update(bytes)
        try downstream.write(bytes)
    }
}

private func validateEntryPath(_ path: String) throws {
    guard !path.isEmpty,
          !path.hasPrefix("/"),
          !path.hasSuffix("/"),
          !path.contains("\\") else {
        throw ZipArchiveError.invalidEntryPath(path)
    }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
        throw ZipArchiveError.invalidEntryPath(path)
    }
}

private func validateZipExtraFields(
    _ bytes: UnsafeRawBufferPointer,
    range: Range<Int>
) throws {
    guard range.lowerBound >= 0, range.upperBound <= bytes.count else {
        throw ZipArchiveError.truncatedArchive
    }
    var offset = range.lowerBound
    while offset < range.upperBound {
        guard offset <= range.upperBound - 4 else {
            throw ZipArchiveError.invalidCentralDirectory
        }
        let headerID = try bytes.littleEndianUInt16(at: offset)
        let payloadLength = Int(try bytes.littleEndianUInt16(at: offset + 2))
        let payloadStart = offset + 4
        guard payloadStart <= range.upperBound - payloadLength else {
            throw ZipArchiveError.invalidCentralDirectory
        }
        guard headerID != zip64ExtraFieldID else {
            throw ZipArchiveError.entryTooLarge("ZIP64")
        }
        offset = payloadStart + payloadLength
    }
}

private let zipDataDescriptorFlag: UInt16 = 0x0008
private let zipUTF8Flag: UInt16 = 0x0800
private let supportedZipGeneralPurposeFlags = zipDataDescriptorFlag | zipUTF8Flag
private let zipDataDescriptorSignature: UInt32 = 0x08074b50
private let zip64ExtraFieldID: UInt16 = 0x0001
