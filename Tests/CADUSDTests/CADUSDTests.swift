import Foundation
import Testing
import CADUSD
import CADUSDC
import CADUSDZ

@Suite("CADUSD")
struct CADUSDTests {
    @Test(.timeLimit(.minutes(1)))
    func usdcReaderReadsBootstrapAndTableOfContents() throws {
        let data = makeUSDCFixture(sections: [
            ("TOKENS", Data([0x01])),
            ("STRINGS", Data([0x02])),
            ("FIELDS", Data([0x03])),
            ("FIELDSETS", Data([0x04])),
            ("PATHS", Data([0x05])),
            ("SPECS", Data([0x06])),
        ])

        let crate = try USDCReader().readCrate(from: data)

        #expect(crate.version == USDCCrateVersion(major: 0, minor: 8, patch: 0))
        #expect(crate.tableOfContentsOffset > USDCCrateFile.bootstrapByteCount)
        #expect(crate.sections.map(\.name) == ["TOKENS", "STRINGS", "FIELDS", "FIELDSETS", "PATHS", "SPECS"])
        #expect(crate.section(named: "TOKENS")?.size == 1)
        try crate.requireStructuralSections()
    }

    @Test(.timeLimit(.minutes(1)))
    func usdcReaderReadsUncompressedLegacyTokens() throws {
        let tokenBytes = nullSeparatedTokenData(["", "Mesh", "points"])
        let tokenSection = makeUSDCTokenSection(version: USDCCrateVersion(major: 0, minor: 3, patch: 0), tokenData: tokenBytes)
        let data = makeUSDCFixture(
            version: USDCCrateVersion(major: 0, minor: 3, patch: 0),
            sections: [
                ("TOKENS", tokenSection),
            ]
        )

        let crate = try USDCReader().readCrate(from: data)

        #expect(try crate.readTokens() == ["", "Mesh", "points"])
    }

    @Test(.timeLimit(.minutes(1)))
    func usdcReaderReadsCompressedTokens() throws {
        let tokenBytes = nullSeparatedTokenData(["", "Mesh", "faceVertexIndices", "subdivisionScheme"])
        let tokenSection = makeUSDCTokenSection(version: USDCCrateVersion(major: 0, minor: 8, patch: 0), tokenData: tokenBytes)
        let data = makeUSDCFixture(sections: [
            ("TOKENS", tokenSection),
        ])

        let crate = try USDCReader().readCrate(from: data)

        #expect(try crate.readTokens() == ["", "Mesh", "faceVertexIndices", "subdivisionScheme"])
    }

    @Test(.timeLimit(.minutes(1)))
    func usdcReaderReadsCompressedStringFieldAndFieldSetTables() throws {
        let version = USDCCrateVersion(major: 0, minor: 8, patch: 0)
        let tokenBytes = nullSeparatedTokenData(["", "specifier", "points", "faceVertexIndices"])
        let fields = [
            USDCCrateField(
                tokenIndex: 1,
                valueRep: USDCCrateValueRep(type: .specifier, isInlined: true, isArray: false, payload: 2)
            ),
            USDCCrateField(
                tokenIndex: 2,
                valueRep: USDCCrateValueRep(type: .vec3f, isInlined: false, isArray: true, payload: 128)
            ),
        ]
        let data = makeUSDCFixture(version: version, sections: [
            ("TOKENS", makeUSDCTokenSection(version: version, tokenData: tokenBytes)),
            ("STRINGS", makeUSDCStringsSection([1, 2])),
            ("FIELDS", makeUSDCFieldsSection(version: version, fields: fields)),
            ("FIELDSETS", makeUSDCFieldSetsSection(version: version, indexes: [0, 1, UInt32.max])),
        ])

        let crate = try USDCReader().readCrate(from: data)

        #expect(try crate.readStringTokenIndexes() == [1, 2])
        #expect(try crate.readStrings() == ["specifier", "points"])
        let parsedFields = try crate.readFields()
        #expect(parsedFields == fields)
        #expect(parsedFields[0].valueRep.type == .specifier)
        #expect(parsedFields[0].valueRep.isInlined)
        #expect(parsedFields[1].valueRep.type == .vec3f)
        #expect(parsedFields[1].valueRep.isArray)
        #expect(parsedFields[1].valueRep.payload == 128)
        #expect(try crate.readFieldSetIndexes() == [0, 1, UInt32.max])
        #expect(try crate.readFieldSets() == [[0, 1]])
    }

    @Test(.timeLimit(.minutes(1)))
    func openUSDFileFormatCrateFixtureReadsStructuralTables() throws {
        let data = try openUSDFixture("testUsdFileFormats/crate.usd")

        let crate = try USDCReader().readCrate(from: data)

        #expect(crate.version == USDCCrateVersion(major: 0, minor: 0, patch: 1))
        try crate.requireStructuralSections()
        #expect(try crate.readTokens().contains("specifier"))
        #expect(try crate.readStringTokenIndexes() == [])
        #expect(!((try crate.readFields()).isEmpty))
        #expect(!((try crate.readFieldSetIndexes()).isEmpty))
    }

    @Test(.timeLimit(.minutes(1)))
    func openUSDSingleUSDCFixtureReadsCompressedStructuralTables() throws {
        let data = try openUSDFixture("testUsdUsdzFileFormat/single/test.usdc")

        let crate = try USDCReader().readCrate(from: data)

        #expect(crate.version == USDCCrateVersion(major: 0, minor: 7, patch: 0))
        try crate.requireStructuralSections()
        #expect(try crate.readTokens().contains("Root_USDC"))
        #expect(!((try crate.readFields()).isEmpty))
        #expect(!((try crate.readFieldSets()).isEmpty))
    }

    @Test(.timeLimit(.minutes(1)))
    func openUSDUSDZFixtureRejectsFirstFileThatIsNotUSDLayer() throws {
        let data = try openUSDFixture("testUsdUsdzFileFormat/first_file_not_usd.usdz")

        #expect(throws: USDImportError.self) {
            _ = try USDZReader().read(from: data)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func openUSDUSDZFixtureWithUSDCDefaultLayerThrowsTypedUSDError() throws {
        let data = try openUSDFixture("testUsdUsdzFileFormat/single_usdc.usdz")

        #expect(throws: USDImportError.self) {
            _ = try USDZReader().read(from: data)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func usdcSceneReaderRequiresStructuralSections() throws {
        let data = makeUSDCFixture(sections: [
            ("TOKENS", Data([0x01])),
        ])

        #expect(throws: USDImportError.self) {
            _ = try USDCReader().read(from: data)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func usdzReaderReadsAlignedUSDADefaultLayer() throws {
        let usda = Data("""
        #usda 1.0
        (
            defaultPrim = "Scene"
            metersPerUnit = 1
            upAxis = "Z"
        )

        def Mesh "Triangle"
        {
            point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
            uniform token subdivisionScheme = "none"
        }
        """.utf8)
        let package = makeUSDZFixture(entries: [
            ("scene.usda", usda),
        ], alignPayloads: true)

        let scene = try USDZReader().read(from: package)

        #expect(scene.defaultPrim == "Scene")
        #expect(scene.upAxis == .z)
        #expect(scene.meshes.count == 1)
        #expect(scene.meshes.first?.points.count == 3)
        #expect(scene.meshes.first?.faceVertexIndices == [0, 1, 2])
    }

    @Test(.timeLimit(.minutes(1)))
    func usdzReaderRejectsUnalignedPayload() throws {
        let usda = Data("""
        #usda 1.0
        (
            metersPerUnit = 1
            upAxis = "Z"
        )

        def Mesh "Triangle"
        {
            point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
        }
        """.utf8)
        let package = makeUSDZFixture(entries: [
            ("scene.usda", usda),
        ], alignPayloads: false)

        #expect(throws: USDImportError.self) {
            _ = try USDZReader().read(from: package)
        }
    }
}

private func makeUSDCFixture(
    version: USDCCrateVersion = USDCCrateVersion(major: 0, minor: 8, patch: 0),
    sections: [(String, Data)]
) -> Data {
    var offset = USDCCrateFile.bootstrapByteCount
    let sectionRanges = sections.map { section -> (name: String, start: Int, size: Int, data: Data) in
        let start = offset
        offset += section.1.count
        return (section.0, start, section.1.count, section.1)
    }
    let tableOfContentsOffset = offset

    var data = Data()
    data.append(contentsOf: USDCReader.fileSignature)
    data.append(contentsOf: [version.major, version.minor, version.patch, 0, 0, 0, 0, 0])
    data.appendLittleEndian(Int64(tableOfContentsOffset))
    for _ in 0..<8 {
        data.appendLittleEndian(Int64(0))
    }
    for section in sectionRanges {
        data.append(section.data)
    }
    data.appendLittleEndian(UInt64(sectionRanges.count))
    for section in sectionRanges {
        data.appendFixedASCII(section.name, byteCount: 16)
        data.appendLittleEndian(Int64(section.start))
        data.appendLittleEndian(Int64(section.size))
    }
    return data
}

private func openUSDFixture(_ relativePath: String) throws -> Data {
    #if SWIFT_PACKAGE
    if let resourceURL = Bundle.module.resourceURL {
        let fixtureURL = resourceURL
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("OpenUSD")
            .appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: fixtureURL.path) {
            return try Data(contentsOf: fixtureURL)
        }
    }
    #endif
    let testFileURL = URL(fileURLWithPath: #filePath)
    let fixturesURL = testFileURL
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("OpenUSD")
    return try Data(contentsOf: fixturesURL.appendingPathComponent(relativePath))
}

private func makeUSDCTokenSection(version: USDCCrateVersion, tokenData: Data) -> Data {
    let tokens = tokenData.filter { $0 == 0 }.count
    var data = Data()
    data.appendLittleEndian(UInt64(tokens))
    if version < USDCCrateVersion(major: 0, minor: 4, patch: 0) {
        data.appendLittleEndian(UInt64(tokenData.count))
        data.append(tokenData)
    } else {
        let compressed = testFastCompression(tokenData)
        data.appendLittleEndian(UInt64(tokenData.count))
        data.appendLittleEndian(UInt64(compressed.count))
        data.append(compressed)
    }
    return data
}

private func makeUSDCStringsSection(_ tokenIndexes: [UInt32]) -> Data {
    var data = Data()
    data.appendLittleEndian(UInt64(tokenIndexes.count))
    for tokenIndex in tokenIndexes {
        data.appendLittleEndian(tokenIndex)
    }
    return data
}

private func makeUSDCFieldsSection(version: USDCCrateVersion, fields: [USDCCrateField]) -> Data {
    var data = Data()
    data.appendLittleEndian(UInt64(fields.count))
    if version < USDCCrateVersion(major: 0, minor: 4, patch: 0) {
        for field in fields {
            data.appendLittleEndian(UInt32(0))
            data.appendLittleEndian(field.tokenIndex)
            data.appendLittleEndian(field.valueRep.rawValue)
        }
    } else {
        data.append(compressedUInt32List(fields.map(\.tokenIndex)))
        var valueRepBytes = Data()
        for field in fields {
            valueRepBytes.appendLittleEndian(field.valueRep.rawValue)
        }
        let compressedValueReps = testFastCompression(valueRepBytes)
        data.appendLittleEndian(UInt64(compressedValueReps.count))
        data.append(compressedValueReps)
    }
    return data
}

private func makeUSDCFieldSetsSection(version: USDCCrateVersion, indexes: [UInt32]) -> Data {
    var data = Data()
    data.appendLittleEndian(UInt64(indexes.count))
    if version < USDCCrateVersion(major: 0, minor: 4, patch: 0) {
        for index in indexes {
            data.appendLittleEndian(index)
        }
    } else {
        data.append(compressedUInt32List(indexes))
    }
    return data
}

private func nullSeparatedTokenData(_ tokens: [String]) -> Data {
    var data = Data()
    for token in tokens {
        data.append(contentsOf: token.utf8)
        data.append(0)
    }
    return data
}

private func compressedUInt32List(_ values: [UInt32]) -> Data {
    let payload = compressedUInt32Payload(values)
    var data = Data()
    data.appendLittleEndian(UInt64(payload.count))
    data.append(payload)
    return data
}

private func compressedUInt32Payload(_ values: [UInt32]) -> Data {
    testFastCompression(integerEncodedData(values))
}

private func integerEncodedData(_ values: [UInt32]) -> Data {
    guard !values.isEmpty else {
        return Data()
    }
    let deltas = integerDeltas(values)
    let commonValue = mostCommonIntegerDelta(deltas)
    var output = Data()
    output.appendLittleEndian(commonValue)
    var codes = [UInt8](repeating: 0, count: (values.count * 2 + 7) / 8)
    var variableIntegers = Data()
    for (index, delta) in deltas.enumerated() {
        let code: UInt8
        if delta == commonValue {
            code = 0
        } else if delta >= Int32(Int8.min), delta <= Int32(Int8.max) {
            code = 1
            variableIntegers.append(UInt8(bitPattern: Int8(truncatingIfNeeded: delta)))
        } else if delta >= Int32(Int16.min), delta <= Int32(Int16.max) {
            code = 2
            variableIntegers.appendLittleEndian(Int16(truncatingIfNeeded: delta))
        } else {
            code = 3
            variableIntegers.appendLittleEndian(delta)
        }
        codes[index / 4] |= code << UInt8((index % 4) * 2)
    }
    output.append(contentsOf: codes)
    output.append(variableIntegers)
    return output
}

private func integerDeltas(_ values: [UInt32]) -> [Int32] {
    var previous = Int32(0)
    return values.map { value in
        let signedValue = Int32(bitPattern: value)
        let delta = signedValue &- previous
        previous = signedValue
        return delta
    }
}

private func mostCommonIntegerDelta(_ deltas: [Int32]) -> Int32 {
    var counts: [Int32: Int] = [:]
    for delta in deltas {
        counts[delta, default: 0] += 1
    }
    return counts.max { lhs, rhs in
        if lhs.value != rhs.value {
            return lhs.value < rhs.value
        }
        return lhs.key < rhs.key
    }?.key ?? 0
}

private func testFastCompression(_ data: Data) -> Data {
    var compressed = Data([0])
    compressed.append(testLZ4LiteralBlock(Array(data)))
    return compressed
}

private func testLZ4LiteralBlock(_ bytes: [UInt8]) -> Data {
    var output = Data()
    var literalCount = bytes.count
    let tokenHighNibble = min(literalCount, 15)
    output.append(UInt8(tokenHighNibble << 4))
    if literalCount >= 15 {
        literalCount -= 15
        while literalCount >= 255 {
            output.append(255)
            literalCount -= 255
        }
        output.append(UInt8(literalCount))
    }
    output.append(contentsOf: bytes)
    return output
}

private func makeUSDZFixture(entries: [(String, Data)], alignPayloads: Bool) -> Data {
    var data = Data()
    var centralRecords: [(path: String, localHeaderOffset: Int, crc: UInt32, size: Int)] = []

    for entry in entries {
        let localHeaderOffset = data.count
        let nameData = Data(entry.0.utf8)
        let crc = testCRC32(entry.1)
        let payloadStartWithoutPadding = localHeaderOffset + 30 + nameData.count
        let extraLength = alignPayloads ? ((64 - (payloadStartWithoutPadding % 64)) % 64) : 0

        data.appendLittleEndian(UInt32(0x04034b50))
        data.appendLittleEndian(UInt16(20))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(crc)
        data.appendLittleEndian(UInt32(entry.1.count))
        data.appendLittleEndian(UInt32(entry.1.count))
        data.appendLittleEndian(UInt16(nameData.count))
        data.appendLittleEndian(UInt16(extraLength))
        data.append(nameData)
        data.append(Data(repeating: 0, count: extraLength))
        data.append(entry.1)
        centralRecords.append((entry.0, localHeaderOffset, crc, entry.1.count))
    }

    let centralDirectoryOffset = data.count
    var centralDirectory = Data()
    for record in centralRecords {
        let nameData = Data(record.path.utf8)
        centralDirectory.appendLittleEndian(UInt32(0x02014b50))
        centralDirectory.appendLittleEndian(UInt16(20))
        centralDirectory.appendLittleEndian(UInt16(20))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(record.crc)
        centralDirectory.appendLittleEndian(UInt32(record.size))
        centralDirectory.appendLittleEndian(UInt32(record.size))
        centralDirectory.appendLittleEndian(UInt16(nameData.count))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt32(0))
        centralDirectory.appendLittleEndian(UInt32(record.localHeaderOffset))
        centralDirectory.append(nameData)
    }
    data.append(centralDirectory)
    data.appendLittleEndian(UInt32(0x06054b50))
    data.appendLittleEndian(UInt16(0))
    data.appendLittleEndian(UInt16(0))
    data.appendLittleEndian(UInt16(centralRecords.count))
    data.appendLittleEndian(UInt16(centralRecords.count))
    data.appendLittleEndian(UInt32(centralDirectory.count))
    data.appendLittleEndian(UInt32(centralDirectoryOffset))
    data.appendLittleEndian(UInt16(0))
    return data
}

private func testCRC32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffff_ffff
    for byte in data {
        let index = Int((crc ^ UInt32(byte)) & 0xff)
        crc = (crc >> 8) ^ testCRC32Table[index]
    }
    return crc ^ 0xffff_ffff
}

private let testCRC32Table: [UInt32] = {
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

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }

    mutating func appendFixedASCII(_ string: String, byteCount: Int) {
        let bytes = Array(string.utf8)
        append(contentsOf: bytes.prefix(byteCount))
        if bytes.count < byteCount {
            append(Data(repeating: 0, count: byteCount - bytes.count))
        }
    }
}
