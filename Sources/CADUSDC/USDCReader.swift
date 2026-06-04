import Foundation
import CADUSD

public struct USDCReader: USDSceneReader {
    public static let fileSignature: [UInt8] = Array("PXR-USDC".utf8)

    public init() {}

    public func readCrate(from data: Data) throws -> USDCCrateFile {
        try USDCCrateFile(data: data)
    }

    public func read(from data: Data) throws -> USDScene {
        let crate = try readCrate(from: data)
        try crate.requireStructuralSections()
        throw USDImportError.notImplemented("USDC crate structural sections were read, but scene materialization is not implemented yet.")
    }
}

public struct USDCCrateVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
    public var major: UInt8
    public var minor: UInt8
    public var patch: UInt8

    public init(major: UInt8, minor: UInt8, patch: UInt8) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: USDCCrateVersion, rhs: USDCCrateVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }
}

public struct USDCCrateSection: Sendable, Equatable {
    public var name: String
    public var start: Int
    public var size: Int

    public init(name: String, start: Int, size: Int) {
        self.name = name
        self.start = start
        self.size = size
    }

    public var range: Range<Int> {
        start..<(start + size)
    }
}

public struct USDCCrateFile: Sendable, Equatable {
    public static let bootstrapByteCount = 88
    public static let sectionRecordByteCount = 32
    public static let oldestSupportedVersion = USDCCrateVersion(major: 0, minor: 0, patch: 1)
    public static let newestKnownVersion = USDCCrateVersion(major: 0, minor: 15, patch: 0)
    public static let structuralSectionNames: Set<String> = [
        "TOKENS",
        "STRINGS",
        "FIELDS",
        "FIELDSETS",
        "PATHS",
        "SPECS",
    ]

    public var version: USDCCrateVersion
    public var tableOfContentsOffset: Int
    public var sections: [USDCCrateSection]
    private var data: Data

    public init(data: Data) throws {
        let reader = USDCBinaryReader(data: data)
        guard data.count >= Self.bootstrapByteCount else {
            throw USDImportError.invalidData("USDC data is too small to contain a bootstrap.")
        }
        guard Array(data.prefix(USDCReader.fileSignature.count)) == USDCReader.fileSignature else {
            throw USDImportError.invalidData("USDC data is missing the PXR-USDC signature.")
        }

        version = USDCCrateVersion(
            major: try reader.readUInt8(at: 8),
            minor: try reader.readUInt8(at: 9),
            patch: try reader.readUInt8(at: 10)
        )
        guard version.major == 0, version <= Self.newestKnownVersion else {
            throw USDImportError.unsupportedFeature("USDC crate version \(version) is newer than the supported reader version.")
        }
        guard version >= Self.oldestSupportedVersion else {
            throw USDImportError.unsupportedFeature("USDC crate version \(version) is older than the supported reader version.")
        }

        let tocOffset64 = try reader.readInt64(at: 16)
        guard tocOffset64 >= Int64(Self.bootstrapByteCount),
              tocOffset64 <= Int64(data.count - MemoryLayout<UInt64>.size) else {
            throw USDImportError.invalidData("USDC table of contents offset is outside the file.")
        }
        guard tocOffset64 <= Int64(Int.max) else {
            throw USDImportError.invalidData("USDC table of contents offset exceeds platform range.")
        }
        tableOfContentsOffset = Int(tocOffset64)

        let sectionCount64 = try reader.readUInt64(at: tableOfContentsOffset)
        guard sectionCount64 <= UInt64(Int.max / Self.sectionRecordByteCount) else {
            throw USDImportError.invalidData("USDC table of contents has too many sections.")
        }
        let sectionCount = Int(sectionCount64)
        let sectionRecordsStart = tableOfContentsOffset + MemoryLayout<UInt64>.size
        let sectionRecordsSize = sectionCount * Self.sectionRecordByteCount
        guard sectionRecordsStart <= data.count - sectionRecordsSize else {
            throw USDImportError.invalidData("USDC table of contents is truncated.")
        }

        var parsedSections: [USDCCrateSection] = []
        var seenNames: Set<String> = []
        for index in 0..<sectionCount {
            let offset = sectionRecordsStart + index * Self.sectionRecordByteCount
            let name = try reader.readNullTerminatedASCII(at: offset, byteCount: 16)
            guard !name.isEmpty else {
                throw USDImportError.invalidData("USDC table of contents contains an empty section name.")
            }
            guard seenNames.insert(name).inserted else {
                throw USDImportError.invalidData("USDC table of contents contains a duplicate section \(name).")
            }
            let start64 = try reader.readInt64(at: offset + 16)
            let size64 = try reader.readInt64(at: offset + 24)
            guard start64 >= 0, size64 >= 0 else {
                throw USDImportError.invalidData("USDC section \(name) has a negative range.")
            }
            guard start64 <= Int64(Int.max), size64 <= Int64(Int.max) else {
                throw USDImportError.invalidData("USDC section \(name) exceeds platform range.")
            }
            let start = Int(start64)
            let size = Int(size64)
            guard start <= data.count, size <= data.count - start else {
                throw USDImportError.invalidData("USDC section \(name) points outside the file.")
            }
            parsedSections.append(USDCCrateSection(name: name, start: start, size: size))
        }
        sections = parsedSections.sorted { lhs, rhs in
            lhs.start < rhs.start
        }
        self.data = data
        try validateSectionLayout(fileSize: data.count)
    }

    public func section(named name: String) -> USDCCrateSection? {
        sections.first { $0.name == name }
    }

    public func requireStructuralSections() throws {
        let presentNames = Set(sections.map(\.name))
        let missingNames = Self.structuralSectionNames.subtracting(presentNames).sorted()
        guard missingNames.isEmpty else {
            throw USDImportError.missingRequiredField("USDC structural sections: \(missingNames.joined(separator: ", "))")
        }
    }

    public func readTokens() throws -> [String] {
        let sectionData = try dataForSection(named: "TOKENS")
        let reader = USDCBinaryReader(data: sectionData)
        var cursor = 0
        let tokenCount = try checkedInt(try reader.readUInt64(at: cursor), label: "USDC token count")
        cursor += MemoryLayout<UInt64>.size
        let tokenBytes: [UInt8]

        if version < USDCCrateVersion(major: 0, minor: 4, patch: 0) {
            let byteCount = try checkedInt(try reader.readUInt64(at: cursor), label: "USDC token byte count")
            cursor += MemoryLayout<UInt64>.size
            tokenBytes = try reader.readBytes(at: cursor, byteCount: byteCount)
        } else {
            let uncompressedSize = try checkedInt(
                try reader.readUInt64(at: cursor),
                label: "USDC token uncompressed byte count"
            )
            cursor += MemoryLayout<UInt64>.size
            let compressedSize = try checkedInt(
                try reader.readUInt64(at: cursor),
                label: "USDC token compressed byte count"
            )
            cursor += MemoryLayout<UInt64>.size
            let compressedBytes = try reader.readBytes(at: cursor, byteCount: compressedSize)
            tokenBytes = try USDCFastCompression.decompress(compressedBytes, expectedByteCount: uncompressedSize)
        }

        return try parseNullTerminatedStrings(
            tokenBytes,
            expectedCount: tokenCount,
            sectionName: "TOKENS"
        )
    }

    private func validateSectionLayout(fileSize: Int) throws {
        var previousUpperBound = Self.bootstrapByteCount
        for section in sections {
            guard section.start >= previousUpperBound else {
                throw USDImportError.invalidData("USDC sections overlap or appear before the bootstrap.")
            }
            guard section.range.upperBound <= fileSize else {
                throw USDImportError.invalidData("USDC section \(section.name) points outside the file.")
            }
            previousUpperBound = section.range.upperBound
        }
        guard tableOfContentsOffset >= previousUpperBound else {
            throw USDImportError.invalidData("USDC table of contents overlaps structural sections.")
        }
    }

    private func dataForSection(named name: String) throws -> Data {
        guard let section = section(named: name) else {
            throw USDImportError.missingRequiredField("USDC section \(name)")
        }
        let start = data.index(data.startIndex, offsetBy: section.start)
        let end = data.index(data.startIndex, offsetBy: section.range.upperBound)
        return Data(data[start..<end])
    }

    private func checkedInt(_ value: UInt64, label: String) throws -> Int {
        guard value <= UInt64(Int.max) else {
            throw USDImportError.invalidData("\(label) exceeds platform range.")
        }
        return Int(value)
    }

    private func parseNullTerminatedStrings(
        _ bytes: [UInt8],
        expectedCount: Int,
        sectionName: String
    ) throws -> [String] {
        guard expectedCount >= 0 else {
            throw USDImportError.invalidData("USDC \(sectionName) count is negative.")
        }
        guard expectedCount == 0 || bytes.last == 0 else {
            throw USDImportError.invalidData("USDC \(sectionName) section is not null-terminated.")
        }
        var strings: [String] = []
        var start = 0
        for index in bytes.indices where bytes[index] == 0 {
            let stringBytes = bytes[start..<index]
            guard let value = String(bytes: stringBytes, encoding: .utf8) else {
                throw USDImportError.invalidData("USDC \(sectionName) contains non-UTF-8 text.")
            }
            strings.append(value)
            start = index + 1
            if strings.count == expectedCount {
                break
            }
        }
        guard strings.count == expectedCount else {
            throw USDImportError.invalidData("USDC \(sectionName) count does not match its encoded strings.")
        }
        return strings
    }
}

private struct USDCBinaryReader {
    let data: Data

    func readUInt8(at offset: Int) throws -> UInt8 {
        guard offset >= 0, offset < data.count else {
            throw USDImportError.invalidData("USDC read is outside the file.")
        }
        return data[data.index(data.startIndex, offsetBy: offset)]
    }

    func readUInt64(at offset: Int) throws -> UInt64 {
        let bytes = try readBytes(at: offset, byteCount: 8)
        var value: UInt64 = 0
        for (index, byte) in bytes.enumerated() {
            value |= UInt64(byte) << UInt64(index * 8)
        }
        return value
    }

    func readInt64(at offset: Int) throws -> Int64 {
        Int64(bitPattern: try readUInt64(at: offset))
    }

    func readNullTerminatedASCII(at offset: Int, byteCount: Int) throws -> String {
        let bytes = try readBytes(at: offset, byteCount: byteCount)
        let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
        let nameBytes = bytes[..<end]
        guard !nameBytes.contains(where: { $0 < 0x20 || $0 > 0x7e }) else {
            throw USDImportError.invalidData("USDC section name is not printable ASCII.")
        }
        guard let name = String(bytes: nameBytes, encoding: .ascii) else {
            throw USDImportError.invalidData("USDC section name is not ASCII.")
        }
        return name
    }

    func readBytes(at offset: Int, byteCount: Int) throws -> [UInt8] {
        guard offset >= 0, byteCount >= 0, offset <= data.count - byteCount else {
            throw USDImportError.invalidData("USDC read is outside the file.")
        }
        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: byteCount)
        return Array(data[start..<end])
    }
}

private enum USDCFastCompression {
    private static let maximumChunkOutputByteCount = 0x7e00_0000

    static func decompress(_ bytes: [UInt8], expectedByteCount: Int) throws -> [UInt8] {
        guard !bytes.isEmpty else {
            throw USDImportError.invalidData("USDC compressed buffer is empty.")
        }
        let chunkCount = Int(bytes[0])
        if chunkCount == 0 {
            let output = try USDCLZ4Block.decompress(
                Array(bytes.dropFirst()),
                maximumOutputByteCount: expectedByteCount
            )
            guard output.count == expectedByteCount else {
                throw USDImportError.invalidData("USDC compressed buffer did not produce the expected byte count.")
            }
            return output
        }

        var cursor = 1
        var output: [UInt8] = []
        output.reserveCapacity(expectedByteCount)
        for _ in 0..<chunkCount {
            guard cursor <= bytes.count - 4 else {
                throw USDImportError.invalidData("USDC compressed chunk header is truncated.")
            }
            let chunkSize = Int(bytes[cursor])
                | (Int(bytes[cursor + 1]) << 8)
                | (Int(bytes[cursor + 2]) << 16)
                | (Int(bytes[cursor + 3]) << 24)
            cursor += 4
            guard chunkSize >= 0, cursor <= bytes.count - chunkSize else {
                throw USDImportError.invalidData("USDC compressed chunk is truncated.")
            }
            let remainingOutput = expectedByteCount - output.count
            let maximumOutput = min(maximumChunkOutputByteCount, remainingOutput)
            let chunk = try USDCLZ4Block.decompress(
                Array(bytes[cursor..<(cursor + chunkSize)]),
                maximumOutputByteCount: maximumOutput
            )
            output.append(contentsOf: chunk)
            cursor += chunkSize
        }
        guard cursor == bytes.count else {
            throw USDImportError.invalidData("USDC compressed buffer has trailing bytes.")
        }
        guard output.count == expectedByteCount else {
            throw USDImportError.invalidData("USDC compressed buffer did not produce the expected byte count.")
        }
        return output
    }
}

private enum USDCLZ4Block {
    static func decompress(_ bytes: [UInt8], maximumOutputByteCount: Int) throws -> [UInt8] {
        guard maximumOutputByteCount >= 0 else {
            throw USDImportError.invalidData("USDC LZ4 output byte count is invalid.")
        }
        var cursor = 0
        var output: [UInt8] = []
        output.reserveCapacity(maximumOutputByteCount)

        while cursor < bytes.count {
            let token = bytes[cursor]
            cursor += 1

            let literalCount = try readLength(
                initialLength: Int(token >> 4),
                bytes: bytes,
                cursor: &cursor
            )
            guard literalCount <= bytes.count - cursor else {
                throw USDImportError.invalidData("USDC LZ4 literal run is truncated.")
            }
            try append(bytes[cursor..<(cursor + literalCount)], to: &output, maximumOutputByteCount: maximumOutputByteCount)
            cursor += literalCount
            guard cursor < bytes.count else {
                break
            }
            guard cursor <= bytes.count - 2 else {
                throw USDImportError.invalidData("USDC LZ4 match offset is truncated.")
            }
            let matchOffset = Int(bytes[cursor]) | (Int(bytes[cursor + 1]) << 8)
            cursor += 2
            guard matchOffset > 0, matchOffset <= output.count else {
                throw USDImportError.invalidData("USDC LZ4 match offset is invalid.")
            }
            let matchCount = try readLength(
                initialLength: Int(token & 0x0f),
                bytes: bytes,
                cursor: &cursor
            ) + 4
            guard output.count <= maximumOutputByteCount - matchCount else {
                throw USDImportError.invalidData("USDC LZ4 output exceeds the expected byte count.")
            }
            for _ in 0..<matchCount {
                output.append(output[output.count - matchOffset])
            }
        }

        return output
    }

    private static func readLength(initialLength: Int, bytes: [UInt8], cursor: inout Int) throws -> Int {
        var length = initialLength
        if initialLength == 15 {
            while true {
                guard cursor < bytes.count else {
                    throw USDImportError.invalidData("USDC LZ4 extended length is truncated.")
                }
                let value = Int(bytes[cursor])
                cursor += 1
                guard length <= Int.max - value else {
                    throw USDImportError.invalidData("USDC LZ4 extended length exceeds platform range.")
                }
                length += value
                if value != 255 {
                    break
                }
            }
        }
        return length
    }

    private static func append(
        _ bytes: ArraySlice<UInt8>,
        to output: inout [UInt8],
        maximumOutputByteCount: Int
    ) throws {
        guard output.count <= maximumOutputByteCount - bytes.count else {
            throw USDImportError.invalidData("USDC LZ4 output exceeds the expected byte count.")
        }
        output.append(contentsOf: bytes)
    }
}
