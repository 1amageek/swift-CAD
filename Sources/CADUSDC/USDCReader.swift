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
        return try USDCSceneMaterializer(crate: crate).readScene()
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

    public func readStringTokenIndexes() throws -> [UInt32] {
        let sectionData = try dataForSection(named: "STRINGS")
        return try readUInt32Vector(from: sectionData, sectionName: "STRINGS")
    }

    public func readStrings() throws -> [String] {
        let tokens = try readTokens()
        let stringTokenIndexes = try readStringTokenIndexes()
        return try stringTokenIndexes.map { tokenIndex in
            let index = try checkedTokenIndex(tokenIndex, tokenCount: tokens.count, sectionName: "STRINGS")
            return tokens[index]
        }
    }

    public func readFields() throws -> [USDCCrateField] {
        let tokenCount = try readTokens().count
        let sectionData = try dataForSection(named: "FIELDS")
        let reader = USDCBinaryReader(data: sectionData)
        let fields: [USDCCrateField]
        if version < USDCCrateVersion(major: 0, minor: 4, patch: 0) {
            var cursor = 0
            let fieldCount = try checkedInt(try reader.readUInt64(at: cursor), label: "USDC field count")
            cursor += MemoryLayout<UInt64>.size
            var parsedFields: [USDCCrateField] = []
            parsedFields.reserveCapacity(fieldCount)
            for _ in 0..<fieldCount {
                _ = try reader.readUInt32(at: cursor)
                cursor += MemoryLayout<UInt32>.size
                let tokenIndex = try reader.readUInt32(at: cursor)
                cursor += MemoryLayout<UInt32>.size
                let valueRep = USDCCrateValueRep(rawValue: try reader.readUInt64(at: cursor))
                cursor += MemoryLayout<UInt64>.size
                parsedFields.append(USDCCrateField(tokenIndex: tokenIndex, valueRep: valueRep))
            }
            try requireNoTrailingBytes(cursor: cursor, byteCount: sectionData.count, sectionName: "FIELDS")
            fields = parsedFields
        } else {
            var cursor = 0
            let fieldCount = try checkedInt(try reader.readUInt64(at: cursor), label: "USDC field count")
            cursor += MemoryLayout<UInt64>.size
            let tokenIndexes = try readCompressedUInt32List(
                reader: reader,
                cursor: &cursor,
                count: fieldCount,
                sectionName: "FIELDS token indexes"
            )
            let repsByteCount = try checkedInt(
                try reader.readUInt64(at: cursor),
                label: "USDC value rep compressed byte count"
            )
            cursor += MemoryLayout<UInt64>.size
            let repsBytes = try reader.readBytes(at: cursor, byteCount: repsByteCount)
            cursor += repsByteCount
            let valueReps = try readCompressedValueReps(repsBytes, count: fieldCount)
            try requireNoTrailingBytes(cursor: cursor, byteCount: sectionData.count, sectionName: "FIELDS")
            fields = zip(tokenIndexes, valueReps).map { tokenIndex, valueRep in
                USDCCrateField(tokenIndex: tokenIndex, valueRep: valueRep)
            }
        }
        for field in fields {
            _ = try checkedTokenIndex(field.tokenIndex, tokenCount: tokenCount, sectionName: "FIELDS")
        }
        return fields
    }

    public func readFieldSetIndexes() throws -> [UInt32] {
        let sectionData = try dataForSection(named: "FIELDSETS")
        let reader = USDCBinaryReader(data: sectionData)
        var fieldSetIndexes: [UInt32]
        if version < USDCCrateVersion(major: 0, minor: 4, patch: 0) {
            fieldSetIndexes = try readUInt32Vector(from: sectionData, sectionName: "FIELDSETS")
        } else {
            var cursor = 0
            let fieldSetIndexCount = try checkedInt(
                try reader.readUInt64(at: cursor),
                label: "USDC field set index count"
            )
            cursor += MemoryLayout<UInt64>.size
            fieldSetIndexes = try readCompressedUInt32List(
                reader: reader,
                cursor: &cursor,
                count: fieldSetIndexCount,
                sectionName: "FIELDSETS"
            )
            try requireNoTrailingBytes(cursor: cursor, byteCount: sectionData.count, sectionName: "FIELDSETS")
        }
        if let last = fieldSetIndexes.last, last != Self.invalidIndex {
            throw USDImportError.invalidData("USDC FIELDSETS section is not terminated by an invalid field index.")
        }
        return fieldSetIndexes
    }

    public func readFieldSets() throws -> [[UInt32]] {
        let fields = try readFields()
        guard fields.count <= Int(UInt32.max) else {
            throw USDImportError.invalidData("USDC FIELDS count exceeds field index range.")
        }
        let fieldSetIndexes = try readFieldSetIndexes()
        var fieldSets: [[UInt32]] = []
        var currentFieldSet: [UInt32] = []
        for fieldIndex in fieldSetIndexes {
            if fieldIndex == Self.invalidIndex {
                fieldSets.append(currentFieldSet)
                currentFieldSet = []
            } else {
                guard fieldIndex < UInt32(fields.count) else {
                    throw USDImportError.invalidData("USDC FIELDSETS contains a field index outside FIELDS.")
                }
                currentFieldSet.append(fieldIndex)
            }
        }
        if !currentFieldSet.isEmpty {
            throw USDImportError.invalidData("USDC FIELDSETS section has unterminated field indexes.")
        }
        return fieldSets
    }

    public func readPaths() throws -> [String] {
        let tokens = try readTokens()
        let section = try requiredSection(named: "PATHS")
        let sectionData = try dataForSection(section)
        let sectionReader = USDCBinaryReader(data: sectionData)
        var cursor = 0
        let pathCount = try checkedInt(try sectionReader.readUInt64(at: cursor), label: "USDC path count")
        cursor += MemoryLayout<UInt64>.size
        guard pathCount <= Int(UInt32.max) else {
            throw USDImportError.invalidData("USDC path count exceeds path index range.")
        }
        var paths = [String](repeating: "", count: pathCount)

        if version < USDCCrateVersion(major: 0, minor: 4, patch: 0) {
            let headerByteCount = version == USDCCrateVersion(major: 0, minor: 0, patch: 1) ? 16 : 12
            var absoluteCursor = section.start + cursor
            var maximumCursor = absoluteCursor
            var visitedPathIndexes: Set<UInt32> = []
            var visitedStreamOffsets: Set<Int> = []
            if pathCount > 0 {
                try readLegacyPathSubtree(
                    cursor: &absoluteCursor,
                    parentPath: nil,
                    section: section,
                    headerByteCount: headerByteCount,
                    paths: &paths,
                    tokens: tokens,
                    visitedPathIndexes: &visitedPathIndexes,
                    visitedStreamOffsets: &visitedStreamOffsets,
                    maximumCursor: &maximumCursor
                )
            }
            guard maximumCursor == section.range.upperBound else {
                throw USDImportError.invalidData("USDC PATHS section has trailing bytes.")
            }
        } else {
            let encodedPathCount = try checkedInt(
                try sectionReader.readUInt64(at: cursor),
                label: "USDC encoded path count"
            )
            cursor += MemoryLayout<UInt64>.size
            let pathIndexes = try readCompressedUInt32List(
                reader: sectionReader,
                cursor: &cursor,
                count: encodedPathCount,
                sectionName: "PATHS path indexes"
            )
            let elementTokenIndexes = try readCompressedInt32List(
                reader: sectionReader,
                cursor: &cursor,
                count: encodedPathCount,
                sectionName: "PATHS element token indexes"
            )
            let jumps = try readCompressedInt32List(
                reader: sectionReader,
                cursor: &cursor,
                count: encodedPathCount,
                sectionName: "PATHS jumps"
            )
            try requireNoTrailingBytes(cursor: cursor, byteCount: sectionData.count, sectionName: "PATHS")
            try buildCompressedPaths(
                pathIndexes: pathIndexes,
                elementTokenIndexes: elementTokenIndexes,
                jumps: jumps,
                paths: &paths,
                tokens: tokens
            )
        }

        return paths
    }

    public func readSpecs() throws -> [USDCCrateSpec] {
        let paths = try readPaths()
        let fieldSetIndexes = try readFieldSetIndexes()
        guard paths.count <= Int(UInt32.max) else {
            throw USDImportError.invalidData("USDC PATHS count exceeds spec path index range.")
        }
        guard fieldSetIndexes.count <= Int(UInt32.max) else {
            throw USDImportError.invalidData("USDC FIELDSETS count exceeds spec field set index range.")
        }

        let sectionData = try dataForSection(named: "SPECS")
        let reader = USDCBinaryReader(data: sectionData)
        var specs: [USDCCrateSpec]
        if version == USDCCrateVersion(major: 0, minor: 0, patch: 1) {
            specs = try readRawSpecs(reader: reader, byteCount: sectionData.count, recordByteCount: 16)
        } else if version < USDCCrateVersion(major: 0, minor: 4, patch: 0) {
            specs = try readRawSpecs(reader: reader, byteCount: sectionData.count, recordByteCount: 12)
        } else {
            var cursor = 0
            let specCount = try checkedInt(try reader.readUInt64(at: cursor), label: "USDC spec count")
            cursor += MemoryLayout<UInt64>.size
            let pathIndexes = try readCompressedUInt32List(
                reader: reader,
                cursor: &cursor,
                count: specCount,
                sectionName: "SPECS path indexes"
            )
            let fieldSetIndexes = try readCompressedUInt32List(
                reader: reader,
                cursor: &cursor,
                count: specCount,
                sectionName: "SPECS field set indexes"
            )
            let specTypes = try readCompressedUInt32List(
                reader: reader,
                cursor: &cursor,
                count: specCount,
                sectionName: "SPECS spec types"
            )
            try requireNoTrailingBytes(cursor: cursor, byteCount: sectionData.count, sectionName: "SPECS")
            specs = try makeSpecs(pathIndexes: pathIndexes, fieldSetIndexes: fieldSetIndexes, specTypes: specTypes)
        }

        try validateSpecs(specs, paths: paths, fieldSetIndexes: fieldSetIndexes)
        return specs
    }

    func readFileBytes(at offset: Int, byteCount: Int) throws -> [UInt8] {
        try USDCBinaryReader(data: data).readBytes(at: offset, byteCount: byteCount)
    }

    func readFileUInt32(at offset: Int) throws -> UInt32 {
        try USDCBinaryReader(data: data).readUInt32(at: offset)
    }

    func readFileUInt64(at offset: Int) throws -> UInt64 {
        try USDCBinaryReader(data: data).readUInt64(at: offset)
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

    private static let invalidIndex = UInt32.max

    private func requiredSection(named name: String) throws -> USDCCrateSection {
        guard let section = section(named: name) else {
            throw USDImportError.missingRequiredField("USDC section \(name)")
        }
        return section
    }

    private func dataForSection(named name: String) throws -> Data {
        let section = try requiredSection(named: name)
        return try dataForSection(section)
    }

    private func dataForSection(_ section: USDCCrateSection) throws -> Data {
        let start = data.index(data.startIndex, offsetBy: section.start)
        let end = data.index(data.startIndex, offsetBy: section.range.upperBound)
        return Data(data[start..<end])
    }

    private func readUInt32Vector(from data: Data, sectionName: String) throws -> [UInt32] {
        let reader = USDCBinaryReader(data: data)
        var cursor = 0
        let count = try checkedInt(try reader.readUInt64(at: cursor), label: "USDC \(sectionName) count")
        cursor += MemoryLayout<UInt64>.size
        var values: [UInt32] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            values.append(try reader.readUInt32(at: cursor))
            cursor += MemoryLayout<UInt32>.size
        }
        try requireNoTrailingBytes(cursor: cursor, byteCount: data.count, sectionName: sectionName)
        return values
    }

    private func readCompressedUInt32List(
        reader: USDCBinaryReader,
        cursor: inout Int,
        count: Int,
        sectionName: String
    ) throws -> [UInt32] {
        let compressedByteCount = try checkedInt(
            try reader.readUInt64(at: cursor),
            label: "USDC \(sectionName) compressed byte count"
        )
        cursor += MemoryLayout<UInt64>.size
        let compressedBytes = try reader.readBytes(at: cursor, byteCount: compressedByteCount)
        cursor += compressedByteCount
        return try USDCIntegerCompression.decompressUInt32(compressedBytes, count: count)
    }

    private func readCompressedInt32List(
        reader: USDCBinaryReader,
        cursor: inout Int,
        count: Int,
        sectionName: String
    ) throws -> [Int32] {
        try readCompressedUInt32List(
            reader: reader,
            cursor: &cursor,
            count: count,
            sectionName: sectionName
        ).map { Int32(bitPattern: $0) }
    }

    private func readRawSpecs(reader: USDCBinaryReader, byteCount: Int, recordByteCount: Int) throws -> [USDCCrateSpec] {
        var cursor = 0
        let specCount = try checkedInt(try reader.readUInt64(at: cursor), label: "USDC spec count")
        cursor += MemoryLayout<UInt64>.size
        var specs: [USDCCrateSpec] = []
        specs.reserveCapacity(specCount)
        for _ in 0..<specCount {
            if recordByteCount == 16 {
                _ = try reader.readUInt32(at: cursor)
                cursor += MemoryLayout<UInt32>.size
            }
            let pathIndex = try reader.readUInt32(at: cursor)
            cursor += MemoryLayout<UInt32>.size
            let fieldSetIndex = try reader.readUInt32(at: cursor)
            cursor += MemoryLayout<UInt32>.size
            let specType = try reader.readUInt32(at: cursor)
            cursor += MemoryLayout<UInt32>.size
            specs.append(
                try makeSpec(pathIndex: pathIndex, fieldSetIndex: fieldSetIndex, specType: specType)
            )
        }
        try requireNoTrailingBytes(cursor: cursor, byteCount: byteCount, sectionName: "SPECS")
        return specs
    }

    private func makeSpecs(
        pathIndexes: [UInt32],
        fieldSetIndexes: [UInt32],
        specTypes: [UInt32]
    ) throws -> [USDCCrateSpec] {
        guard pathIndexes.count == fieldSetIndexes.count, pathIndexes.count == specTypes.count else {
            throw USDImportError.invalidData("USDC SPECS columns have mismatched counts.")
        }
        var specs: [USDCCrateSpec] = []
        specs.reserveCapacity(pathIndexes.count)
        for index in pathIndexes.indices {
            specs.append(
                try makeSpec(
                    pathIndex: pathIndexes[index],
                    fieldSetIndex: fieldSetIndexes[index],
                    specType: specTypes[index]
                )
            )
        }
        return specs
    }

    private func makeSpec(pathIndex: UInt32, fieldSetIndex: UInt32, specType: UInt32) throws -> USDCCrateSpec {
        guard let crateSpecType = USDCCrateSpecType(rawValue: specType), crateSpecType.isConcrete else {
            throw USDImportError.invalidData("USDC SPECS contains an invalid spec type.")
        }
        return USDCCrateSpec(pathIndex: pathIndex, fieldSetIndex: fieldSetIndex, specType: crateSpecType)
    }

    private func validateSpecs(
        _ specs: [USDCCrateSpec],
        paths: [String],
        fieldSetIndexes: [UInt32]
    ) throws {
        var seenPathIndexes: Set<UInt32> = []
        for spec in specs {
            guard spec.pathIndex < UInt32(paths.count) else {
                throw USDImportError.invalidData("USDC SPECS contains a path index outside PATHS.")
            }
            guard !paths[Int(spec.pathIndex)].isEmpty else {
                throw USDImportError.invalidData("USDC SPECS contains an empty path.")
            }
            guard seenPathIndexes.insert(spec.pathIndex).inserted else {
                throw USDImportError.invalidData("USDC SPECS contains a repeated path.")
            }
            guard spec.fieldSetIndex < UInt32(fieldSetIndexes.count) else {
                throw USDImportError.invalidData("USDC SPECS contains a field set index outside FIELDSETS.")
            }
            let fieldSetIndex = Int(spec.fieldSetIndex)
            if fieldSetIndex > 0, fieldSetIndexes[fieldSetIndex - 1] != Self.invalidIndex {
                throw USDImportError.invalidData("USDC SPECS field set index does not start a field set.")
            }
        }
    }

    private func readLegacyPathSubtree(
        cursor: inout Int,
        parentPath: String?,
        section: USDCCrateSection,
        headerByteCount: Int,
        paths: inout [String],
        tokens: [String],
        visitedPathIndexes: inout Set<UInt32>,
        visitedStreamOffsets: inout Set<Int>,
        maximumCursor: inout Int
    ) throws {
        let reader = USDCBinaryReader(data: data)
        var currentParentPath = parentPath
        while true {
            guard cursor >= section.start, cursor <= section.range.upperBound - headerByteCount else {
                throw USDImportError.invalidData("USDC PATHS legacy tree is truncated.")
            }
            let headerOffset = cursor
            guard visitedStreamOffsets.insert(headerOffset).inserted else {
                throw USDImportError.invalidData("USDC PATHS legacy tree contains a repeated stream offset.")
            }
            let usesLegacyPadding = headerByteCount == 16
            let pathIndexOffset = headerOffset + (usesLegacyPadding ? MemoryLayout<UInt32>.size : 0)
            let tokenIndexOffset = pathIndexOffset + MemoryLayout<UInt32>.size
            let bitsOffset = tokenIndexOffset + MemoryLayout<UInt32>.size
            let pathIndex = try reader.readUInt32(at: pathIndexOffset)
            let elementTokenIndex = try reader.readUInt32(at: tokenIndexOffset)
            let bits = try reader.readUInt8(at: bitsOffset)
            try validatePathHeader(pathIndex: pathIndex, bits: bits, paths: paths, visitedPathIndexes: &visitedPathIndexes)

            cursor += headerByteCount
            maximumCursor = max(maximumCursor, cursor)
            let path = try makePath(parentPath: currentParentPath, tokenIndex: Int32(bitPattern: elementTokenIndex), bits: bits, tokens: tokens)
            paths[Int(pathIndex)] = path

            let hasChild = bits & Self.pathHasChildBit != 0
            let hasSibling = bits & Self.pathHasSiblingBit != 0
            if hasChild {
                if hasSibling {
                    let siblingOffset = try reader.readInt64(at: cursor)
                    cursor += MemoryLayout<Int64>.size
                    maximumCursor = max(maximumCursor, cursor)
                    guard siblingOffset >= Int64(section.start),
                          siblingOffset <= Int64(section.range.upperBound - headerByteCount),
                          siblingOffset <= Int64(Int.max) else {
                        throw USDImportError.invalidData("USDC PATHS legacy sibling offset is outside PATHS.")
                    }
                    var childCursor = cursor
                    try readLegacyPathSubtree(
                        cursor: &childCursor,
                        parentPath: path,
                        section: section,
                        headerByteCount: headerByteCount,
                        paths: &paths,
                        tokens: tokens,
                        visitedPathIndexes: &visitedPathIndexes,
                        visitedStreamOffsets: &visitedStreamOffsets,
                        maximumCursor: &maximumCursor
                    )
                    var siblingCursor = Int(siblingOffset)
                    try readLegacyPathSubtree(
                        cursor: &siblingCursor,
                        parentPath: currentParentPath,
                        section: section,
                        headerByteCount: headerByteCount,
                        paths: &paths,
                        tokens: tokens,
                        visitedPathIndexes: &visitedPathIndexes,
                        visitedStreamOffsets: &visitedStreamOffsets,
                        maximumCursor: &maximumCursor
                    )
                    cursor = max(childCursor, siblingCursor)
                    return
                }
                currentParentPath = path
            } else if !hasSibling {
                return
            }
        }
    }

    private func buildCompressedPaths(
        pathIndexes: [UInt32],
        elementTokenIndexes: [Int32],
        jumps: [Int32],
        paths: inout [String],
        tokens: [String]
    ) throws {
        guard pathIndexes.count == elementTokenIndexes.count, pathIndexes.count == jumps.count else {
            throw USDImportError.invalidData("USDC PATHS columns have mismatched counts.")
        }
        var seenPathIndexes: Set<UInt32> = []
        for index in pathIndexes.indices {
            try validatePathIndex(pathIndexes[index], paths: paths, visitedPathIndexes: &seenPathIndexes)
            _ = try checkedSignedTokenIndex(elementTokenIndexes[index], tokenCount: tokens.count, sectionName: "PATHS")
            guard jumps[index] >= -2 else {
                throw USDImportError.invalidData("USDC PATHS contains an invalid jump.")
            }
        }
        guard !pathIndexes.isEmpty else {
            return
        }
        var visitedEncodedIndexes: Set<Int> = []
        _ = try buildCompressedPathSubtree(
            startIndex: 0,
            parentPath: nil,
            pathIndexes: pathIndexes,
            elementTokenIndexes: elementTokenIndexes,
            jumps: jumps,
            paths: &paths,
            tokens: tokens,
            visitedEncodedIndexes: &visitedEncodedIndexes
        )
        guard visitedEncodedIndexes.count == pathIndexes.count else {
            throw USDImportError.invalidData("USDC PATHS does not encode every path item.")
        }
    }

    private func buildCompressedPathSubtree(
        startIndex: Int,
        parentPath: String?,
        pathIndexes: [UInt32],
        elementTokenIndexes: [Int32],
        jumps: [Int32],
        paths: inout [String],
        tokens: [String],
        visitedEncodedIndexes: inout Set<Int>
    ) throws -> Int {
        var currentIndex = startIndex
        var currentParentPath = parentPath
        while true {
            guard currentIndex < pathIndexes.count else {
                throw USDImportError.invalidData("USDC PATHS encoding references a missing item.")
            }
            let thisIndex = currentIndex
            currentIndex += 1
            guard visitedEncodedIndexes.insert(thisIndex).inserted else {
                throw USDImportError.invalidData("USDC PATHS encoding visits an item more than once.")
            }

            let pathIndex = Int(pathIndexes[thisIndex])
            let path = try makePath(
                parentPath: currentParentPath,
                tokenIndex: elementTokenIndexes[thisIndex],
                bits: 0,
                tokens: tokens
            )
            paths[pathIndex] = path

            let jump = jumps[thisIndex]
            let hasChild = jump > 0 || jump == -1
            let hasSibling = jump >= 0
            if hasChild {
                if hasSibling {
                    let siblingIndex = thisIndex + Int(jump)
                    guard siblingIndex > thisIndex, siblingIndex < pathIndexes.count else {
                        throw USDImportError.invalidData("USDC PATHS sibling jump is outside encoded paths.")
                    }
                    _ = try buildCompressedPathSubtree(
                        startIndex: currentIndex,
                        parentPath: path,
                        pathIndexes: pathIndexes,
                        elementTokenIndexes: elementTokenIndexes,
                        jumps: jumps,
                        paths: &paths,
                        tokens: tokens,
                        visitedEncodedIndexes: &visitedEncodedIndexes
                    )
                    _ = try buildCompressedPathSubtree(
                        startIndex: siblingIndex,
                        parentPath: currentParentPath,
                        pathIndexes: pathIndexes,
                        elementTokenIndexes: elementTokenIndexes,
                        jumps: jumps,
                        paths: &paths,
                        tokens: tokens,
                        visitedEncodedIndexes: &visitedEncodedIndexes
                    )
                    return currentIndex
                }
                currentParentPath = path
            } else if !hasSibling {
                return currentIndex
            }
        }
    }

    private func makePath(parentPath: String?, tokenIndex: Int32, bits: UInt8, tokens: [String]) throws -> String {
        if let parentPath {
            let token = tokens[try checkedSignedTokenIndex(tokenIndex, tokenCount: tokens.count, sectionName: "PATHS")]
            let isPropertyPath = bits & Self.pathIsPrimPropertyBit != 0 || tokenIndex < 0
            return appendPathElement(token, to: parentPath, isPropertyPath: isPropertyPath)
        }
        return "/"
    }

    private func appendPathElement(_ element: String, to parentPath: String, isPropertyPath: Bool) -> String {
        if isPropertyPath {
            return "\(parentPath).\(element)"
        }
        if parentPath == "/" {
            return "/\(element)"
        }
        return "\(parentPath)/\(element)"
    }

    private func validatePathHeader(
        pathIndex: UInt32,
        bits: UInt8,
        paths: [String],
        visitedPathIndexes: inout Set<UInt32>
    ) throws {
        try validatePathIndex(pathIndex, paths: paths, visitedPathIndexes: &visitedPathIndexes)
        guard bits & ~Self.pathHeaderKnownBits == 0 else {
            throw USDImportError.invalidData("USDC PATHS contains unknown path header bits.")
        }
    }

    private func validatePathIndex(
        _ pathIndex: UInt32,
        paths: [String],
        visitedPathIndexes: inout Set<UInt32>
    ) throws {
        guard pathIndex < UInt32(paths.count) else {
            throw USDImportError.invalidData("USDC PATHS contains a path index outside PATHS.")
        }
        guard visitedPathIndexes.insert(pathIndex).inserted else {
            throw USDImportError.invalidData("USDC PATHS contains a repeated path index.")
        }
    }

    private func checkedSignedTokenIndex(_ tokenIndex: Int32, tokenCount: Int, sectionName: String) throws -> Int {
        guard tokenIndex != Int32.min else {
            throw USDImportError.invalidData("USDC \(sectionName) contains an invalid signed token index.")
        }
        let absoluteTokenIndex = tokenIndex < 0 ? -tokenIndex : tokenIndex
        guard tokenCount <= Int(UInt32.max),
              UInt32(bitPattern: absoluteTokenIndex) < UInt32(tokenCount) else {
            throw USDImportError.invalidData("USDC \(sectionName) contains a token index outside TOKENS.")
        }
        return Int(absoluteTokenIndex)
    }

    private func readCompressedValueReps(_ compressedBytes: [UInt8], count: Int) throws -> [USDCCrateValueRep] {
        guard count <= Int.max / MemoryLayout<UInt64>.size else {
            throw USDImportError.invalidData("USDC value rep count exceeds platform range.")
        }
        let byteCount = count * MemoryLayout<UInt64>.size
        let valueBytes = try USDCFastCompression.decompress(
            compressedBytes,
            expectedByteCount: byteCount
        )
        let reader = USDCBinaryReader(data: Data(valueBytes))
        var valueReps: [USDCCrateValueRep] = []
        valueReps.reserveCapacity(count)
        var cursor = 0
        for _ in 0..<count {
            valueReps.append(USDCCrateValueRep(rawValue: try reader.readUInt64(at: cursor)))
            cursor += MemoryLayout<UInt64>.size
        }
        return valueReps
    }

    private func checkedInt(_ value: UInt64, label: String) throws -> Int {
        guard value <= UInt64(Int.max) else {
            throw USDImportError.invalidData("\(label) exceeds platform range.")
        }
        return Int(value)
    }

    private func checkedTokenIndex(_ tokenIndex: UInt32, tokenCount: Int, sectionName: String) throws -> Int {
        guard tokenCount <= Int(UInt32.max),
              tokenIndex != Self.invalidIndex,
              tokenIndex < UInt32(tokenCount) else {
            throw USDImportError.invalidData("USDC \(sectionName) contains a token index outside TOKENS.")
        }
        return Int(tokenIndex)
    }

    private func requireNoTrailingBytes(cursor: Int, byteCount: Int, sectionName: String) throws {
        guard cursor == byteCount else {
            throw USDImportError.invalidData("USDC \(sectionName) section has trailing bytes.")
        }
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

    private static let pathHasChildBit: UInt8 = 1 << 0
    private static let pathHasSiblingBit: UInt8 = 1 << 1
    private static let pathIsPrimPropertyBit: UInt8 = 1 << 2
    private static let pathHeaderKnownBits = pathHasChildBit | pathHasSiblingBit | pathIsPrimPropertyBit
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

    func readUInt32(at offset: Int) throws -> UInt32 {
        let bytes = try readBytes(at: offset, byteCount: 4)
        var value: UInt32 = 0
        for (index, byte) in bytes.enumerated() {
            value |= UInt32(byte) << UInt32(index * 8)
        }
        return value
    }

    func readInt32(at offset: Int) throws -> Int32 {
        Int32(bitPattern: try readUInt32(at: offset))
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

enum USDCFastCompression {
    private static let maximumChunkOutputByteCount = 0x7e00_0000

    static func decompress(_ bytes: [UInt8], expectedByteCount: Int) throws -> [UInt8] {
        let output = try decompress(bytes, maximumOutputByteCount: expectedByteCount)
        guard output.count == expectedByteCount else {
            throw USDImportError.invalidData("USDC compressed buffer did not produce the expected byte count.")
        }
        return output
    }

    static func decompress(_ bytes: [UInt8], maximumOutputByteCount: Int) throws -> [UInt8] {
        guard maximumOutputByteCount >= 0 else {
            throw USDImportError.invalidData("USDC compressed buffer output byte count is invalid.")
        }
        guard !bytes.isEmpty else {
            guard maximumOutputByteCount == 0 else {
                throw USDImportError.invalidData("USDC compressed buffer is empty.")
            }
            return []
        }
        let chunkCount = Int(bytes[0])
        if chunkCount == 0 {
            return try USDCLZ4Block.decompress(
                Array(bytes.dropFirst()),
                maximumOutputByteCount: maximumOutputByteCount
            )
        }

        var cursor = 1
        var output: [UInt8] = []
        output.reserveCapacity(maximumOutputByteCount)
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
            let remainingOutput = maximumOutputByteCount - output.count
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
            try append(
                bytes[cursor..<(cursor + literalCount)],
                to: &output,
                maximumOutputByteCount: maximumOutputByteCount
            )
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
