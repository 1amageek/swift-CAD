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

    private func readBytes(at offset: Int, byteCount: Int) throws -> [UInt8] {
        guard offset >= 0, byteCount >= 0, offset <= data.count - byteCount else {
            throw USDImportError.invalidData("USDC read is outside the file.")
        }
        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: byteCount)
        return Array(data[start..<end])
    }
}
