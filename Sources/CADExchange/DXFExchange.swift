import Foundation
import CADCore
import CADIR

public struct DXFExchange: Sendable {
    private let tolerance: ModelingTolerance
    private let resourceLimits: ExchangeResourceLimits

    public init(
        tolerance: ModelingTolerance,
        resourceLimits: ExchangeResourceLimits = .standard
    ) {
        self.tolerance = tolerance
        self.resourceLimits = resourceLimits
    }

    public func write(meshes: [BodyID: Mesh], unit: LengthUnit = .meter, to sink: any ByteSink) throws {
        guard !meshes.isEmpty else {
            throw ExportError.emptyMesh
        }
        let sortedMeshes = meshes.sorted(by: { $0.key.description < $1.key.description })
        var resources = try ExchangeResourceAccountant(limits: resourceLimits, format: .dxf)
        for (_, mesh) in sortedMeshes {
            try mesh.validate(tolerance: tolerance)
            try resources.recordEntities(1 + mesh.positions.count + mesh.indices.count / 3)
            try resources.recordIterations(mesh.positions.count + mesh.indices.count)
        }
        let output = try ExchangeBoundedByteSink(
            downstream: sink,
            limits: resourceLimits,
            format: .dxf
        )
        try output.writeUTF8("""
        0
        SECTION
        2
        HEADER
        9
        $ACADVER
        1
        AC1027
        9
        $INSUNITS
        70
        \(dxfUnitCode(for: unit))
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        """)
        for (_, mesh) in sortedMeshes {
            var index = 0
            while index < mesh.indices.count {
                let points = [
                    mesh.positions[Int(mesh.indices[index])],
                    mesh.positions[Int(mesh.indices[index + 1])],
                    mesh.positions[Int(mesh.indices[index + 2])]
                ]
                try writeFaceEntity(points: points, unit: unit, to: output)
                index += 3
            }
        }
        try output.writeUTF8("""

        0
        ENDSEC
        0
        EOF
        """)
    }

    public func `import`(_ source: any ByteSource, unit: LengthUnit = .meter) throws -> ImportedExchangeModel {
        var resources = try ExchangeResourceAccountant(limits: resourceLimits, format: .dxf)
        try resources.validateInputByteCount(source.count)
        try resources.recordIterations(source.count)
        return try source.withNoCopyData { data in
            guard data.allSatisfy({ $0 < 0x80 }) else {
                throw ImportError.invalidData("DXF data must contain ASCII bytes only.")
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw ImportError.invalidData("DXF data is not valid ASCII text.")
            }
            return try importText(text, unit: unit, resources: &resources)
        }
    }

    private func importText(
        _ text: String,
        unit: LengthUnit,
        resources: inout ExchangeResourceAccountant
    ) throws -> ImportedExchangeModel {
        let tokens = try dxfTokens(from: text)
        try validateDXFTerminator(tokens)
        try validateDXFSections(tokens)
        try validateDXFVersion(in: tokens)
        let importUnit = try dxfLengthUnit(in: tokens, fallback: unit)
        let entityRanges = try dxfEntitiesSectionRanges(in: tokens)
        try rejectDXF3DFacesOutsideEntities(in: tokens, entityRanges: entityRanges)
        try rejectUnsupportedDXFRecordsOutsideSections(in: tokens)
        try rejectUnsupportedDXFEntities(in: tokens, entityRanges: entityRanges)
        var positions: [Point3D] = []
        var indices: [UInt32] = []
        for range in entityRanges {
            var cursor = range.lowerBound
            while cursor + 1 < range.upperBound {
                if tokens[cursor] == "0", tokens[cursor + 1].uppercased() == "3DFACE" {
                    let face = try parseFace(tokens: tokens, cursor: &cursor, unit: importUnit)
                    try resources.recordEntities(1 + face.count / 3)
                    for point in face {
                        guard UInt64(positions.count) < UInt64(UInt32.max) else {
                            throw ImportError.invalidData("DXF mesh vertex count exceeds UInt32 range.")
                        }
                        positions.append(point)
                        indices.append(UInt32(positions.count - 1))
                    }
                } else {
                    cursor += 2
                }
            }
        }
        let mesh = Mesh(positions: positions, normals: [], indices: indices)
        try validateImportedMesh(mesh, formatName: "DXF", tolerance: tolerance)
        try resources.checkTime()
        return ImportedExchangeModel(format: .dxf, meshes: [BodyID(): mesh], units: UnitSystem(length: importUnit, angle: .radian))
    }

    private func writeFaceEntity(points: [Point3D], unit: LengthUnit, to sink: any ByteSink) throws {
        let fourth = points[2]
        let values: [(String, Double)] = [
            ("10", points[0].x), ("20", points[0].y), ("30", points[0].z),
            ("11", points[1].x), ("21", points[1].y), ("31", points[1].z),
            ("12", points[2].x), ("22", points[2].y), ("32", points[2].z),
            ("13", fourth.x), ("23", fourth.y), ("33", fourth.z)
        ]
        try sink.writeUTF8("\n0\n3DFACE\n8\nSwiftCAD")
        for (code, value) in values {
            let converted = try checkedExportUnitValue(
                unit.fromInternal(value),
                formatName: "DXF",
                component: "group \(code)"
            )
            try sink.writeUTF8("\n\(code)\n\(converted)")
        }
    }

    private func parseFace(tokens: [String], cursor: inout Int, unit: LengthUnit) throws -> [Point3D] {
        cursor += 2
        var values: [String: Double] = [:]
        let coordinateCodes = Set(["10", "20", "30", "11", "21", "31", "12", "22", "32", "13", "23", "33"])
        while cursor + 1 < tokens.count {
            let code = tokens[cursor]
            let rawValue = tokens[cursor + 1]
            if code == "0" {
                break
            }
            if coordinateCodes.contains(code) {
                guard values[code] == nil else {
                    throw ImportError.invalidData("DXF 3DFACE contains a duplicate coordinate group.")
                }
                guard let value = Double(rawValue), value.isFinite else {
                    throw ImportError.invalidData("DXF 3DFACE contains an invalid coordinate value.")
                }
                values[code] = value
            }
            cursor += 2
        }
        let pointCodes = [("10", "20", "30"), ("11", "21", "31"), ("12", "22", "32")]
        let points = try pointCodes.map { xCode, yCode, zCode in
            guard let x = values[xCode], let y = values[yCode], let z = values[zCode] else {
                throw ImportError.invalidData("DXF 3DFACE is missing coordinates.")
            }
            let point = Point3D(x: unit.toInternal(x), y: unit.toInternal(y), z: unit.toInternal(z))
            guard point.x.isFinite,
                  point.y.isFinite,
                  point.z.isFinite else {
                throw ImportError.invalidData("DXF 3DFACE contains a non-finite coordinate.")
            }
            return point
        }
        return try triangulatedFace(firstThree: points, values: values, unit: unit)
    }

    private func triangulatedFace(
        firstThree points: [Point3D],
        values: [String: Double],
        unit: LengthUnit
    ) throws -> [Point3D] {
        let fourthCodes = ["13", "23", "33"]
        let presentCodes = fourthCodes.filter { values[$0] != nil }
        guard !presentCodes.isEmpty else {
            return points
        }
        guard let x = values["13"],
              let y = values["23"],
              let z = values["33"] else {
            throw ImportError.invalidData("DXF 3DFACE fourth point is incomplete.")
        }
        let fourthPoint = Point3D(x: unit.toInternal(x), y: unit.toInternal(y), z: unit.toInternal(z))
        guard fourthPoint.x.isFinite,
              fourthPoint.y.isFinite,
              fourthPoint.z.isFinite else {
            throw ImportError.invalidData("DXF 3DFACE fourth point contains a non-finite coordinate.")
        }
        if fourthPoint.isApproximatelyEqual(
            to: points[2],
            tolerance: tolerance.distance
        ) {
            return points
        }
        let firstDiagonal = [
            points[0], points[1], points[2],
            points[0], points[2], fourthPoint,
        ]
        let secondDiagonal = [
            points[0], points[1], fourthPoint,
            points[1], points[2], fourthPoint,
        ]
        let firstScore = minimumTriangleAreaMagnitude(firstDiagonal)
        let secondScore = minimumTriangleAreaMagnitude(secondDiagonal)
        let selected = firstScore >= secondScore ? firstDiagonal : secondDiagonal
        guard max(firstScore, secondScore) > tolerance.distance * tolerance.distance else {
            throw ImportError.invalidData("DXF quadrilateral 3DFACE cannot be triangulated without a degenerate triangle.")
        }
        return selected
    }

    private func minimumTriangleAreaMagnitude(_ points: [Point3D]) -> Double {
        min(
            (points[1] - points[0]).cross(points[2] - points[0]).length,
            (points[4] - points[3]).cross(points[5] - points[3]).length
        )
    }
}

private func dxfUnitCode(for unit: LengthUnit) -> Int {
    switch unit {
    case .inch:
        1
    case .foot:
        2
    case .millimeter:
        4
    case .centimeter:
        5
    case .meter:
        6
    case .kilometer:
        7
    case .micrometer:
        13
    }
}

private func dxfLengthUnit(for code: Int) -> LengthUnit? {
    switch code {
    case 1:
        .inch
    case 2:
        .foot
    case 4:
        .millimeter
    case 5:
        .centimeter
    case 6:
        .meter
    case 7:
        .kilometer
    case 13:
        .micrometer
    default:
        nil
    }
}

private func dxfLengthUnit(in tokens: [String], fallback: LengthUnit) throws -> LengthUnit {
    guard let headerRange = try dxfHeaderSectionRange(in: tokens) else {
        return fallback
    }
    var resolvedUnit: LengthUnit?
    var cursor = headerRange.lowerBound
    while cursor + 1 < headerRange.upperBound {
        if tokens[cursor] == "9", tokens[cursor + 1] == "$INSUNITS" {
            guard resolvedUnit == nil else {
                throw ImportError.invalidData("DXF HEADER contains duplicate $INSUNITS declarations.")
            }
            guard cursor + 3 < headerRange.upperBound, tokens[cursor + 2] == "70" else {
                throw ImportError.invalidData("DXF $INSUNITS is missing a unit code.")
            }
            guard let code = Int(tokens[cursor + 3]) else {
                throw ImportError.invalidData("DXF $INSUNITS contains a non-integer unit code.")
            }
            if code == 0 {
                resolvedUnit = fallback
                cursor += 4
                continue
            }
            guard let unit = dxfLengthUnit(for: code) else {
                throw ImportError.invalidData("Unsupported DXF $INSUNITS code \(code).")
            }
            resolvedUnit = unit
            cursor += 4
            continue
        }
        cursor += 2
    }
    return resolvedUnit ?? fallback
}

private func validateDXFVersion(in tokens: [String]) throws {
    guard let headerRange = try dxfHeaderSectionRange(in: tokens) else {
        return
    }
    var version: String?
    var cursor = headerRange.lowerBound
    while cursor + 1 < headerRange.upperBound {
        if tokens[cursor] == "9", tokens[cursor + 1] == "$ACADVER" {
            guard version == nil else {
                throw ImportError.invalidData("DXF HEADER contains duplicate $ACADVER declarations.")
            }
            guard cursor + 3 < headerRange.upperBound,
                  tokens[cursor + 2] == "1" else {
                throw ImportError.invalidData("DXF $ACADVER is missing a version value.")
            }
            version = tokens[cursor + 3].uppercased()
            cursor += 4
            continue
        }
        cursor += 2
    }
    if let version, version != "AC1027" {
        throw ImportError.unsupportedVersion("DXF version \(version) is not AC1027.")
    }
}

private func dxfTokens(from text: String) throws -> [String] {
    var tokens = text.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    while tokens.last == "" {
        tokens.removeLast()
    }
    guard !tokens.isEmpty else {
        throw ImportError.invalidData("DXF token stream is empty.")
    }
    guard tokens.allSatisfy({ !$0.isEmpty }) else {
        throw ImportError.invalidData("DXF token stream contains an empty group code or value.")
    }
    guard tokens.count.isMultiple(of: 2) else {
        throw ImportError.invalidData("DXF token stream must contain complete group code/value pairs.")
    }
    var codeIndex = 0
    while codeIndex < tokens.count {
        guard Int(tokens[codeIndex]) != nil else {
            throw ImportError.invalidData("DXF token stream contains a non-integer group code.")
        }
        codeIndex += 2
    }
    return tokens
}

private func validateDXFTerminator(_ tokens: [String]) throws {
    guard tokens.count >= 2,
          tokens[tokens.count - 2] == "0",
          tokens[tokens.count - 1].uppercased() == "EOF" else {
        throw ImportError.invalidData("DXF token stream must terminate with EOF.")
    }
    var cursor = 0
    let terminalOffset = tokens.count - 2
    while cursor + 1 < terminalOffset {
        if tokens[cursor] == "0", tokens[cursor + 1].uppercased() == "EOF" {
            throw ImportError.invalidData("DXF EOF marker must be the final record.")
        }
        cursor += 2
    }
}

private func validateDXFSections(_ tokens: [String]) throws {
    var cursor = 0
    var headerSectionCount = 0
    while cursor + 3 < tokens.count {
        guard tokens[cursor] == "0",
              tokens[cursor + 1].uppercased() == "SECTION" else {
            cursor += 2
            continue
        }
        guard tokens[cursor + 2] == "2" else {
            throw ImportError.invalidData("DXF SECTION is missing a section name.")
        }
        let sectionName = tokens[cursor + 3].uppercased()
        switch sectionName {
        case "HEADER":
            headerSectionCount += 1
            guard headerSectionCount == 1 else {
                throw ImportError.invalidData("DXF HEADER section is duplicated.")
            }
        case "ENTITIES":
            break
        default:
            throw ImportError.invalidData("Unsupported DXF section \(sectionName).")
        }
        cursor += 4
    }
}

private func dxfHeaderSectionRange(in tokens: [String]) throws -> Range<Int>? {
    var cursor = 0
    while cursor + 3 < tokens.count {
        if tokens[cursor] == "0",
           tokens[cursor + 1].uppercased() == "SECTION",
           tokens[cursor + 2] == "2",
           tokens[cursor + 3].uppercased() == "HEADER" {
            let start = cursor + 4
            var end = start
            while end + 1 < tokens.count {
                if tokens[end] == "0", tokens[end + 1].uppercased() == "ENDSEC" {
                    return start..<end
                }
                if tokens[end] == "0", tokens[end + 1].uppercased() == "SECTION" {
                    throw ImportError.invalidData("DXF HEADER section is unterminated.")
                }
                end += 2
            }
            throw ImportError.invalidData("DXF HEADER section is unterminated.")
        }
        cursor += 2
    }
    return nil
}

private func dxfEntitiesSectionRanges(in tokens: [String]) throws -> [Range<Int>] {
    var ranges: [Range<Int>] = []
    var cursor = 0
    while cursor + 3 < tokens.count {
        if tokens[cursor] == "0",
           tokens[cursor + 1].uppercased() == "SECTION",
           tokens[cursor + 2] == "2",
           tokens[cursor + 3].uppercased() == "ENTITIES" {
            let start = cursor + 4
            var end = start
            while end + 1 < tokens.count {
                if tokens[end] == "0", tokens[end + 1].uppercased() == "ENDSEC" {
                    ranges.append(start..<end)
                    cursor = end + 2
                    break
                }
                if tokens[end] == "0", tokens[end + 1].uppercased() == "SECTION" {
                    throw ImportError.invalidData("DXF ENTITIES section is unterminated.")
                }
                end += 2
            }
            guard end + 1 < tokens.count else {
                throw ImportError.invalidData("DXF ENTITIES section is unterminated.")
            }
        } else {
            cursor += 2
        }
    }
    return ranges
}

private func rejectDXF3DFacesOutsideEntities(
    in tokens: [String],
    entityRanges: [Range<Int>]
) throws {
    var cursor = 0
    while cursor + 1 < tokens.count {
        if tokens[cursor] == "0", tokens[cursor + 1].uppercased() == "3DFACE" {
            let isInsideEntitySection = entityRanges.contains { range in
                range.contains(cursor)
            }
            guard isInsideEntitySection else {
                throw ImportError.invalidData("DXF 3DFACE is outside the ENTITIES section.")
            }
        }
        cursor += 2
    }
}

private func rejectUnsupportedDXFRecordsOutsideSections(in tokens: [String]) throws {
    var cursor = 0
    var insideSection = false
    while cursor + 1 < tokens.count {
        if !insideSection, tokens[cursor] != "0" {
            throw ImportError.invalidData("Unsupported DXF group code \(tokens[cursor]) outside a section.")
        }
        if tokens[cursor] == "0" {
            let recordType = tokens[cursor + 1].uppercased()
            switch recordType {
            case "SECTION":
                guard !insideSection else {
                    throw ImportError.invalidData("Nested DXF SECTION records are not supported.")
                }
                insideSection = true
            case "ENDSEC":
                guard insideSection else {
                    throw ImportError.invalidData("DXF ENDSEC is outside a section.")
                }
                insideSection = false
            case "EOF":
                guard !insideSection else {
                    throw ImportError.invalidData("DXF EOF is inside a section.")
                }
            default:
                guard insideSection else {
                    throw ImportError.invalidData("Unsupported DXF record \(recordType) outside a section.")
                }
            }
        }
        cursor += 2
    }
}

private func rejectUnsupportedDXFEntities(
    in tokens: [String],
    entityRanges: [Range<Int>]
) throws {
    for range in entityRanges {
        var cursor = range.lowerBound
        while cursor + 1 < range.upperBound {
            if tokens[cursor] == "0" {
                let entityType = tokens[cursor + 1].uppercased()
                guard entityType == "3DFACE" else {
                    throw ImportError.invalidData("Unsupported DXF entity \(entityType).")
                }
            }
            cursor += 2
        }
    }
}
