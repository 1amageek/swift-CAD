import Foundation
import CADCore
import CADIR

public struct STEPExchange: Sendable {
    public init() {}

    public func write(meshes: [BodyID: Mesh], units: UnitSystem = .meters, to sink: any ByteSink) throws {
        guard !meshes.isEmpty else {
            throw ExportError.emptyMesh
        }

        let lengthUnit = units.length
        try sink.writeUTF8("""
        ISO-10303-21;
        HEADER;
        FILE_DESCRIPTION(('Swift-CAD AP242 tessellated shape export'),'2;1');
        FILE_NAME('swift-cad.step','',('Swift-CAD'),('Swift-CAD'),'Swift-CAD','Swift-CAD','');
        FILE_SCHEMA(('AP242_MANAGED_MODEL_BASED_3D_ENGINEERING_MIM_LF'));
        ENDSEC;
        DATA;
        #1=APPLICATION_CONTEXT('mechanical design');
        #2=APPLICATION_PROTOCOL_DEFINITION('international standard','ap242_managed_model_based_3d_engineering',2014,#1);
        #3=PRODUCT_CONTEXT('',#1,'mechanical');
        #4=PRODUCT('SWIFT_CAD_MODEL','Swift-CAD Model','',(#3));
        #5=PRODUCT_DEFINITION_FORMATION('1','',#4);
        #6=PRODUCT_DEFINITION_CONTEXT('part definition',#1,'design');
        #7=PRODUCT_DEFINITION('design','',#5,#6);
        #8=PRODUCT_DEFINITION_SHAPE('','',#7);
        #9=(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNIT_ASSIGNED_CONTEXT((#10,#11,#12)) REPRESENTATION_CONTEXT('Swift-CAD 3D context','3D'));
        #10=\(stepLengthUnitEntity(for: lengthUnit));
        #11=(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.));
        #12=(NAMED_UNIT(*) SOLID_ANGLE_UNIT() SI_UNIT($,.STERADIAN.));
        #13=LENGTH_MEASURE_WITH_UNIT(LENGTH_MEASURE(\(stepNumber(lengthUnit.metersPerUnit))),#15);
        #14=DIMENSIONAL_EXPONENTS(1.,0.,0.,0.,0.,0.,0.);
        #15=(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.));
        """)

        var nextID = 16
        for (bodyID, mesh) in meshes.sorted(by: { $0.key.description < $1.key.description }) {
            try mesh.validate()
            let name = stepName("Body_\(bodyID.rawValue.uuidString.replacingOccurrences(of: "-", with: "_"))")
            let pointListID = nextID
            let faceSetID = nextID + 1
            let representationID = nextID + 2
            let relationshipID = nextID + 3
            nextID += 4

            try sink.writeUTF8("\n#\(pointListID)=CARTESIAN_POINT_LIST_3D('\(name)',(")
            for (index, point) in mesh.positions.enumerated() {
                let x = try checkedExportUnitValue(
                    lengthUnit.fromInternal(point.x),
                    formatName: "STEP",
                    component: "point.x"
                )
                let y = try checkedExportUnitValue(
                    lengthUnit.fromInternal(point.y),
                    formatName: "STEP",
                    component: "point.y"
                )
                let z = try checkedExportUnitValue(
                    lengthUnit.fromInternal(point.z),
                    formatName: "STEP",
                    component: "point.z"
                )
                if index > 0 {
                    try sink.writeUTF8(",")
                }
                try sink.writeUTF8("(\(stepNumber(x)),\(stepNumber(y)),\(stepNumber(z)))")
            }
            try sink.writeUTF8("));")
            try sink.writeUTF8("\n#\(faceSetID)=TRIANGULATED_FACE_SET('\(name)',#\(pointListID),$,$,.T.,(")
            var isFirstFace = true
            for triangleIndex in stride(from: 0, to: mesh.indices.count, by: 3) {
                if !isFirstFace {
                    try sink.writeUTF8(",")
                }
                isFirstFace = false
                try sink.writeUTF8("(\(mesh.indices[triangleIndex] + 1),\(mesh.indices[triangleIndex + 1] + 1),\(mesh.indices[triangleIndex + 2] + 1))")
            }
            try sink.writeUTF8("),$);")
            try sink.writeUTF8("\n#\(representationID)=TESSELLATED_SHAPE_REPRESENTATION('\(name)',(#\(faceSetID)),#9);")
            try sink.writeUTF8("\n#\(relationshipID)=SHAPE_DEFINITION_REPRESENTATION(#8,#\(representationID));")
        }

        try sink.writeUTF8("""
        
        ENDSEC;
        END-ISO-10303-21;
        """)
    }

    public func `import`(_ source: any ByteSource) throws -> ImportedExchangeModel {
        try source.withNoCopyData { data in
            guard let text = String(data: data, encoding: .utf8) else {
                throw ImportError.invalidData("STEP data is not UTF-8.")
            }
            return try importText(text)
        }
    }

    private func importText(_ text: String) throws -> ImportedExchangeModel {
        try validateSTEPExchangeEnvelope(in: text)

        let dataSections = try stepDataSections(in: text)
        try rejectSTEPEntityMarkersOutsideDataSections(in: text, dataRanges: dataSections.map(\.contentRange))
        guard !dataSections.isEmpty else {
            throw ImportError.invalidData("Missing STEP DATA section.")
        }
        let entities = try stepEntities(in: dataSections.map(\.content).joined(separator: "\n"))
        try validateSupportedSTEPEntities(entities)
        let lengthUnit = try stepLengthUnit(in: entities)
        var pointLists: [Int: [Point3D]] = [:]
        for (id, entity) in entities where entity.hasPrefix("CARTESIAN_POINT_LIST_3D") {
            pointLists[id] = try stepPoints(from: entity, unit: lengthUnit)
        }

        var meshes: [BodyID: Mesh] = [:]
        var referencedPointListIDs = Set<Int>()
        for (_, entity) in entities where entity.hasPrefix("TRIANGULATED_FACE_SET") {
            guard let pointListID = stepFirstReference(in: entity),
                  let points = pointLists[pointListID] else {
                throw ImportError.missingRequiredEntity("CARTESIAN_POINT_LIST_3D")
            }
            referencedPointListIDs.insert(pointListID)
            let indices = try stepFaceIndices(from: entity, pointCount: points.count)
            let mesh = Mesh(positions: points, normals: [], indices: indices)
            try validateImportedMesh(mesh, formatName: "STEP")
            meshes[BodyID()] = mesh
        }

        if let unreferencedPointListID = Set(pointLists.keys).subtracting(referencedPointListIDs).sorted().first {
            throw ImportError.invalidData("STEP point list #\(unreferencedPointListID) is not referenced by a face set.")
        }
        guard !meshes.isEmpty else {
            throw ImportError.missingRequiredEntity("TRIANGULATED_FACE_SET")
        }
        return ImportedExchangeModel(
            format: .step,
            meshes: meshes,
            units: UnitSystem(length: lengthUnit, angle: .radian)
        )
    }
}

private func validateSupportedSTEPEntities(_ entities: [Int: String]) throws {
    for id in entities.keys.sorted() {
        guard let entity = entities[id] else {
            continue
        }
        guard isSupportedSTEPEntity(entity) else {
            throw ImportError.invalidData("Unsupported STEP entity #\(id).")
        }
    }
}

private func isSupportedSTEPEntity(_ entity: String) -> Bool {
    let syntax = normalizedSTEPText(stepSyntaxOutsideStrings(in: entity))
    let supportedPrefixes = [
        "APPLICATION_CONTEXT(",
        "APPLICATION_PROTOCOL_DEFINITION(",
        "PRODUCT_CONTEXT(",
        "PRODUCT(",
        "PRODUCT_DEFINITION_FORMATION(",
        "PRODUCT_DEFINITION_CONTEXT(",
        "PRODUCT_DEFINITION(",
        "PRODUCT_DEFINITION_SHAPE(",
        "CARTESIAN_POINT_LIST_3D(",
        "TRIANGULATED_FACE_SET(",
        "TESSELLATED_SHAPE_REPRESENTATION(",
        "SHAPE_DEFINITION_REPRESENTATION(",
        "LENGTH_MEASURE_WITH_UNIT(",
        "DIMENSIONAL_EXPONENTS("
    ]
    if supportedPrefixes.contains(where: { syntax.hasPrefix($0) }) {
        return true
    }
    guard syntax.hasPrefix("("), syntax.hasSuffix(")") else {
        return false
    }
    return isSupportedSTEPComplexEntity(syntax)
}

private func isSupportedSTEPComplexEntity(_ syntax: String) -> Bool {
    if syntax.contains("GEOMETRIC_REPRESENTATION_CONTEXT("),
       syntax.contains("GLOBAL_UNIT_ASSIGNED_CONTEXT(("),
       syntax.contains("REPRESENTATION_CONTEXT(") {
        return true
    }
    if syntax.contains("PLANE_ANGLE_UNIT()"),
       syntax.contains("SI_UNIT($,.RADIAN.)") {
        return true
    }
    if syntax.contains("SOLID_ANGLE_UNIT()"),
       syntax.contains("SI_UNIT($,.STERADIAN.)") {
        return true
    }
    if syntax.contains("LENGTH_UNIT()"),
       syntax.contains("NAMED_UNIT(") {
        return syntax.contains("SI_UNIT($,.METRE.)")
            || syntax.contains("SI_UNIT(.MICRO.,.METRE.)")
            || syntax.contains("SI_UNIT(.MILLI.,.METRE.)")
            || syntax.contains("SI_UNIT(.CENTI.,.METRE.)")
            || syntax.contains("SI_UNIT(.KILO.,.METRE.)")
            || syntax.contains("CONVERSION_BASED_UNIT(")
    }
    return false
}

private func stepLengthUnitEntity(for unit: LengthUnit) -> String {
    switch unit {
    case .micrometer:
        "(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MICRO.,.METRE.))"
    case .meter:
        "(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT($,.METRE.))"
    case .kilometer:
        "(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.KILO.,.METRE.))"
    case .millimeter:
        "(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.))"
    case .centimeter:
        "(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.CENTI.,.METRE.))"
    case .inch:
        "(CONVERSION_BASED_UNIT('INCH',#13) LENGTH_UNIT() NAMED_UNIT(#14))"
    case .foot:
        "(CONVERSION_BASED_UNIT('FOOT',#13) LENGTH_UNIT() NAMED_UNIT(#14))"
    }
}

private func stepLengthUnit(in entities: [Int: String]) throws -> LengthUnit {
    let unitIDs = try stepGlobalUnitReferenceIDs(in: entities)
    guard !unitIDs.isEmpty else {
        return .meter
    }
    var lengthUnits: [LengthUnit] = []
    for unitID in unitIDs {
        guard let entity = entities[unitID] else {
            throw ImportError.missingRequiredEntity("STEP GLOBAL_UNIT_ASSIGNED_CONTEXT reference #\(unitID)")
        }
        if let unit = try stepLengthUnit(from: entity, entities: entities) {
            lengthUnits.append(unit)
        }
    }
    guard !lengthUnits.isEmpty else {
        throw ImportError.missingRequiredEntity("STEP GLOBAL_UNIT_ASSIGNED_CONTEXT LENGTH_UNIT")
    }
    guard lengthUnits.count == 1, let lengthUnit = lengthUnits.first else {
        throw ImportError.invalidData("STEP GLOBAL_UNIT_ASSIGNED_CONTEXT must reference exactly one LENGTH_UNIT.")
    }
    return lengthUnit
}

private func stepGlobalUnitReferenceIDs(in entities: [Int: String]) throws -> [Int] {
    var ids: [Int] = []
    for id in entities.keys.sorted() {
        guard let entity = entities[id] else {
            continue
        }
        let syntax = normalizedSTEPText(stepSyntaxOutsideStrings(in: entity))
        guard let range = syntax.range(of: "GLOBAL_UNIT_ASSIGNED_CONTEXT((") else {
            continue
        }
        guard let listContent = stepGlobalUnitReferenceListContent(in: syntax, from: range.upperBound) else {
            throw ImportError.invalidData("STEP GLOBAL_UNIT_ASSIGNED_CONTEXT reference list is malformed.")
        }
        ids.append(contentsOf: try stepReferenceListIDs(in: listContent, label: "STEP GLOBAL_UNIT_ASSIGNED_CONTEXT"))
    }
    return ids
}

private func stepGlobalUnitReferenceListContent(in text: String, from start: String.Index) -> String? {
    var cursor = start
    var depth = 1
    while cursor < text.endIndex {
        if text[cursor] == "(" {
            depth += 1
        } else if text[cursor] == ")" {
            depth -= 1
            if depth == 0 {
                return String(text[start..<cursor])
            }
        }
        cursor = text.index(after: cursor)
    }
    return nil
}

private func stepReferenceListIDs(in text: String, label: String) throws -> [Int] {
    let references = text
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard !references.isEmpty else {
        throw ImportError.invalidData("\(label) reference list is empty.")
    }
    return try references.map { reference in
        guard reference.first == "#" else {
            throw ImportError.invalidData("\(label) reference is malformed.")
        }
        let numberStart = reference.index(after: reference.startIndex)
        let numberText = reference[numberStart...]
        guard !numberText.isEmpty,
              numberText.allSatisfy(\.isNumber),
              let id = Int(numberText) else {
            throw ImportError.invalidData("\(label) reference is malformed.")
        }
        return id
    }
}

private func stepReferenceIDs(in text: String) -> [Int] {
    var ids: [Int] = []
    var searchStart = text.startIndex
    while let hashIndex = text[searchStart...].firstIndex(of: "#") {
        var numberEnd = text.index(after: hashIndex)
        while numberEnd < text.endIndex, text[numberEnd].isNumber {
            numberEnd = text.index(after: numberEnd)
        }
        if let id = Int(text[text.index(after: hashIndex)..<numberEnd]) {
            ids.append(id)
        }
        searchStart = numberEnd
    }
    return ids
}

private func stepLengthUnit(from entity: String, entities: [Int: String]) throws -> LengthUnit? {
    let normalized = normalizedSTEPText(entity)
    let syntax = normalizedSTEPText(stepSyntaxOutsideStrings(in: entity))
    guard syntax.contains("LENGTH_UNIT()") else {
        return nil
    }
    if syntax.hasPrefix("(CONVERSION_BASED_UNIT(,"),
       normalized.hasPrefix("(CONVERSION_BASED_UNIT('INCH',") {
        try validateSTEPConversionFactor(for: .inch, in: entity, entities: entities)
        return .inch
    }
    if syntax.hasPrefix("(CONVERSION_BASED_UNIT(,"),
       normalized.hasPrefix("(CONVERSION_BASED_UNIT('FOOT',") {
        try validateSTEPConversionFactor(for: .foot, in: entity, entities: entities)
        return .foot
    }
    if syntax.contains("SI_UNIT(.MICRO.,.METRE.)") {
        return .micrometer
    }
    if syntax.contains("SI_UNIT(.MILLI.,.METRE.)") {
        return .millimeter
    }
    if syntax.contains("SI_UNIT(.CENTI.,.METRE.)") {
        return .centimeter
    }
    if syntax.contains("SI_UNIT(.KILO.,.METRE.)") {
        return .kilometer
    }
    if syntax.contains("SI_UNIT($,.METRE.)") {
        return .meter
    }
    throw ImportError.invalidData("Unsupported STEP length unit.")
}

private func validateSTEPConversionFactor(
    for unit: LengthUnit,
    in conversionEntity: String,
    entities: [Int: String]
) throws {
    guard let measureID = stepFirstReference(in: conversionEntity),
          let measureEntity = entities[measureID] else {
        throw ImportError.missingRequiredEntity("STEP conversion length factor")
    }
    let factor = try stepConversionFactor(from: measureEntity, entities: entities)
    let tolerance = max(1.0e-12, unit.metersPerUnit * 1.0e-12)
    guard abs(factor - unit.metersPerUnit) <= tolerance else {
        throw ImportError.invalidData("STEP conversion length factor does not match \(unit.rawValue).")
    }
}

private func stepConversionFactor(from entity: String, entities: [Int: String]) throws -> Double {
    let syntax = normalizedSTEPText(stepSyntaxOutsideStrings(in: entity))
    let prefix = "LENGTH_MEASURE_WITH_UNIT(LENGTH_MEASURE("
    guard syntax.hasPrefix(prefix) else {
        throw ImportError.invalidData("STEP conversion length factor is malformed.")
    }
    let valueStart = syntax.index(syntax.startIndex, offsetBy: prefix.count)
    guard let valueEnd = syntax[valueStart...].firstIndex(of: ")") else {
        throw ImportError.invalidData("STEP conversion length factor is malformed.")
    }
    let valueText = String(syntax[valueStart..<valueEnd])
    guard let factor = Double(valueText), factor.isFinite, factor > 0.0 else {
        throw ImportError.invalidData("STEP conversion length factor must be a positive finite number.")
    }
    let references = stepReferenceIDs(in: syntax)
    guard references.count == 1,
          let unitEntity = entities[references[0]] else {
        throw ImportError.missingRequiredEntity("STEP conversion length base unit")
    }
    guard try stepSILengthUnit(from: unitEntity) == .meter else {
        throw ImportError.invalidData("STEP conversion length factor must reference metres.")
    }
    return factor
}

private func stepSILengthUnit(from entity: String) throws -> LengthUnit? {
    let syntax = normalizedSTEPText(stepSyntaxOutsideStrings(in: entity))
    guard syntax.contains("LENGTH_UNIT()") else {
        return nil
    }
    if syntax.contains("SI_UNIT(.MICRO.,.METRE.)") {
        return .micrometer
    }
    if syntax.contains("SI_UNIT(.MILLI.,.METRE.)") {
        return .millimeter
    }
    if syntax.contains("SI_UNIT(.CENTI.,.METRE.)") {
        return .centimeter
    }
    if syntax.contains("SI_UNIT(.KILO.,.METRE.)") {
        return .kilometer
    }
    if syntax.contains("SI_UNIT($,.METRE.)") {
        return .meter
    }
    throw ImportError.invalidData("Unsupported STEP length unit.")
}

private func normalizedSTEPText(_ text: String) -> String {
    text
        .uppercased()
        .filter { !$0.isWhitespace }
}

private func stepTriangleIndices(from mesh: Mesh) -> [(UInt32, UInt32, UInt32)] {
    var triangles: [(UInt32, UInt32, UInt32)] = []
    var index = 0
    while index < mesh.indices.count {
        let first = mesh.indices[index] + 1
        let second = mesh.indices[index + 1] + 1
        let third = mesh.indices[index + 2] + 1
        triangles.append((first, second, third))
        index += 3
    }
    return triangles
}

private struct STEPDataSection {
    let contentRange: Range<String.Index>
    let content: String
}

private func validateSTEPExchangeEnvelope(in text: String) throws {
    guard let startMarker = nextSTEPMarker("ISO-10303-21;", in: text, from: text.startIndex) else {
        throw ImportError.invalidData("Missing STEP header.")
    }
    guard text[..<startMarker.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ImportError.invalidData("STEP header must be the first exchange record.")
    }
    guard let endMarker = nextSTEPMarker("END-ISO-10303-21;", in: text, from: startMarker.upperBound) else {
        throw ImportError.invalidData("STEP exchange terminator is missing.")
    }
    guard text[endMarker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ImportError.invalidData("STEP exchange terminator must be the final record.")
    }
}

private func stepDataSections(in text: String) throws -> [STEPDataSection] {
    var sections: [STEPDataSection] = []
    var searchStart = text.startIndex
    while let dataMarker = nextSTEPMarker("DATA;", in: text, from: searchStart) {
        guard let endMarker = nextSTEPMarker("ENDSEC;", in: text, from: dataMarker.upperBound) else {
            throw ImportError.invalidData("STEP DATA section is unterminated.")
        }
        let contentRange = dataMarker.upperBound..<endMarker.lowerBound
        sections.append(STEPDataSection(
            contentRange: contentRange,
            content: String(text[contentRange])
        ))
        searchStart = endMarker.upperBound
    }
    return sections
}

private func rejectSTEPEntityMarkersOutsideDataSections(
    in text: String,
    dataRanges: [Range<String.Index>]
) throws {
    var searchStart = text.startIndex
    while let hashIndex = nextSTEPHashOutsideString(in: text, from: searchStart) {
        if dataRanges.contains(where: { $0.contains(hashIndex) }) {
            searchStart = text.index(after: hashIndex)
            continue
        }
        var numberEnd = text.index(after: hashIndex)
        while numberEnd < text.endIndex, text[numberEnd].isNumber {
            numberEnd = text.index(after: numberEnd)
        }
        guard numberEnd > text.index(after: hashIndex) else {
            throw ImportError.invalidData("STEP entity or reference marker is malformed.")
        }
        throw ImportError.invalidData("STEP entity or reference marker is outside the DATA section.")
    }
}

private func nextSTEPMarker(
    _ marker: String,
    in text: String,
    from start: String.Index
) -> Range<String.Index>? {
    var cursor = start
    var inString = false
    while cursor < text.endIndex {
        if updateSTEPStringState(in: text, cursor: &cursor, inString: &inString) {
            continue
        }
        if !inString,
           hasSTEPMarkerBoundary(before: cursor, in: text),
           let range = stepMarkerRange(marker, in: text, at: cursor) {
            return range
        }
        cursor = text.index(after: cursor)
    }
    return nil
}

private func stepMarkerRange(
    _ marker: String,
    in text: String,
    at index: String.Index
) -> Range<String.Index>? {
    var cursor = index
    for markerCharacter in marker {
        guard cursor < text.endIndex,
              String(text[cursor]).uppercased() == String(markerCharacter) else {
            return nil
        }
        cursor = text.index(after: cursor)
    }
    return index..<cursor
}

private func hasSTEPMarkerBoundary(before index: String.Index, in text: String) -> Bool {
    guard index > text.startIndex else {
        return true
    }
    let previous = text[text.index(before: index)]
    return !isSTEPIdentifierCharacter(previous)
}

private func isSTEPIdentifierCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber || character == "_"
}

private func stepEntities(in text: String) throws -> [Int: String] {
    var entities: [Int: String] = [:]
    var searchStart = text.startIndex
    while let hashIndex = nextSTEPHashOutsideString(in: text, from: searchStart) {
        var numberEnd = text.index(after: hashIndex)
        while numberEnd < text.endIndex, text[numberEnd].isNumber {
            numberEnd = text.index(after: numberEnd)
        }

        guard numberEnd > text.index(after: hashIndex),
              let id = Int(text[text.index(after: hashIndex)..<numberEnd]) else {
            throw ImportError.invalidData("STEP entity or reference marker is malformed.")
        }
        guard let syntaxIndex = nextNonWhitespaceIndex(in: text, from: numberEnd) else {
            throw ImportError.invalidData("STEP entity or reference marker is unterminated.")
        }
        guard text[syntaxIndex] == "=" else {
            guard isSTEPReferenceTerminator(text[syntaxIndex]) else {
                throw ImportError.invalidData("STEP entity or reference marker is malformed.")
            }
            searchStart = syntaxIndex
            continue
        }

        let entityStart = text.index(after: syntaxIndex)
        var cursor = entityStart
        var inString = false
        while cursor < text.endIndex {
            let character = text[cursor]
            if character == "'" {
                let next = text.index(after: cursor)
                if next < text.endIndex, text[next] == "'" {
                    cursor = text.index(after: next)
                    continue
                }
                inString.toggle()
            }
            if character == ";", !inString {
                guard entities[id] == nil else {
                    throw ImportError.invalidData("STEP entity ID #\(id) is duplicated.")
                }
                entities[id] = String(text[entityStart..<cursor])
                searchStart = text.index(after: cursor)
                break
            }
            cursor = text.index(after: cursor)
        }
        if cursor >= text.endIndex {
            throw ImportError.invalidData("STEP entity #\(id) is unterminated.")
        }
    }
    return entities
}

private func nextNonWhitespaceIndex(in text: String, from start: String.Index) -> String.Index? {
    var cursor = start
    while cursor < text.endIndex {
        guard text[cursor].isWhitespace else {
            return cursor
        }
        cursor = text.index(after: cursor)
    }
    return nil
}

private func isSTEPReferenceTerminator(_ character: Character) -> Bool {
    character == "," || character == ")" || character == ";"
}

private func stepPoints(from entity: String, unit: LengthUnit) throws -> [Point3D] {
    guard let content = firstDoubleParenthesizedContent(in: entity) else {
        throw ImportError.invalidData("STEP point list has no coordinates.")
    }
    return try tupleContents(in: content).map { tuple in
        let values = try numericValues(from: tuple, expectedCount: 3, label: "STEP point")
        return Point3D(
            x: unit.toInternal(values[0]),
            y: unit.toInternal(values[1]),
            z: unit.toInternal(values[2])
        )
    }
}

private func stepFaceIndices(from entity: String, pointCount: Int) throws -> [UInt32] {
    guard let content = firstDoubleParenthesizedContent(in: entity) else {
        throw ImportError.invalidData("STEP face set has no indices.")
    }
    var indices: [UInt32] = []
    for tuple in try tupleContents(in: content) {
        let values = try numericValues(from: tuple, expectedCount: 3, label: "STEP face index")
        for value in values {
            guard value.rounded(.towardZero) == value else {
                throw ImportError.invalidData("STEP face index is not an integer.")
            }
            let maximumOneBasedIndex = min(Double(pointCount), Double(UInt32.max) + 1.0)
            guard value >= 1.0, value <= maximumOneBasedIndex else {
                throw ImportError.invalidData("STEP face index is out of range.")
            }
            let oneBasedIndex = Int(value)
            let zeroBasedIndex = oneBasedIndex - 1
            indices.append(UInt32(zeroBasedIndex))
        }
    }
    return indices
}

private func stepFirstReference(in entity: String) -> Int? {
    guard let hashIndex = nextSTEPHashOutsideString(in: entity, from: entity.startIndex) else {
        return nil
    }
    var numberEnd = entity.index(after: hashIndex)
    while numberEnd < entity.endIndex, entity[numberEnd].isNumber {
        numberEnd = entity.index(after: numberEnd)
    }
    return Int(entity[entity.index(after: hashIndex)..<numberEnd])
}

func firstDoubleParenthesizedContent(in text: String) -> String? {
    var searchStart = text.startIndex
    while let first = nextSTEPCharacterOutsideString("(", in: text, from: searchStart) {
        let second = text.index(after: first)
        if second < text.endIndex, text[second] == "(" {
            var depth = 0
            var cursor = first
            var inString = false
            while cursor < text.endIndex {
                if updateSTEPStringState(in: text, cursor: &cursor, inString: &inString) {
                    continue
                }
                if inString {
                    cursor = text.index(after: cursor)
                    continue
                }
                if text[cursor] == "(" {
                    depth += 1
                } else if text[cursor] == ")" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[text.index(after: first)..<cursor])
                    }
                }
                cursor = text.index(after: cursor)
            }
            return nil
        }
        searchStart = second
    }
    return nil
}

private func nextSTEPHashOutsideString(in text: String, from start: String.Index) -> String.Index? {
    nextSTEPCharacterOutsideString("#", in: text, from: start)
}

private func nextSTEPCharacterOutsideString(
    _ target: Character,
    in text: String,
    from start: String.Index
) -> String.Index? {
    var cursor = start
    var inString = false
    while cursor < text.endIndex {
        if updateSTEPStringState(in: text, cursor: &cursor, inString: &inString) {
            continue
        }
        if !inString, text[cursor] == target {
            return cursor
        }
        cursor = text.index(after: cursor)
    }
    return nil
}

private func updateSTEPStringState(in text: String, cursor: inout String.Index, inString: inout Bool) -> Bool {
    guard text[cursor] == "'" else {
        return false
    }
    let next = text.index(after: cursor)
    if next < text.endIndex, text[next] == "'" {
        cursor = text.index(after: next)
        return true
    }
    inString.toggle()
    cursor = next
    return true
}

private func stepSyntaxOutsideStrings(in text: String) -> String {
    var output = ""
    var cursor = text.startIndex
    var inString = false
    while cursor < text.endIndex {
        if updateSTEPStringState(in: text, cursor: &cursor, inString: &inString) {
            continue
        }
        if !inString {
            output.append(text[cursor])
        }
        cursor = text.index(after: cursor)
    }
    return output
}

func tupleContents(in text: String) throws -> [String] {
    var tuples: [String] = []
    var tupleStart: String.Index?
    var depth = 0
    var cursor = text.startIndex
    while cursor < text.endIndex {
        let character = text[cursor]
        if character == "(" {
            if depth == 0 {
                tupleStart = text.index(after: cursor)
            }
            depth += 1
        } else if character == ")" {
            guard depth > 0 else {
                throw ImportError.invalidData("STEP tuple list contains unbalanced parentheses.")
            }
            depth -= 1
            if depth == 0, let start = tupleStart {
                tuples.append(String(text[start..<cursor]))
                tupleStart = nil
            }
        } else if depth == 0, character != ",", !character.isWhitespace {
            throw ImportError.invalidData("STEP tuple list contains unexpected content.")
        }
        cursor = text.index(after: cursor)
    }
    guard depth == 0 else {
        throw ImportError.invalidData("STEP tuple list contains unbalanced parentheses.")
    }
    guard !tuples.isEmpty else {
        throw ImportError.invalidData("STEP tuple list contains no tuples.")
    }
    return tuples
}

func numericValues(from tuple: String, expectedCount: Int, label: String) throws -> [Double] {
    let values = tuple
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard values.count == expectedCount else {
        throw ImportError.invalidData("\(label) has \(values.count) values.")
    }
    return try values.map { value in
        guard !value.isEmpty,
              let number = Double(value),
              number.isFinite else {
            throw ImportError.invalidData("\(label) contains a non-numeric value.")
        }
        return number
    }
}

func stepNumber(_ value: Double) -> String {
    String(format: "%.17g", locale: Locale(identifier: "en_US_POSIX"), value)
}

func stepName(_ value: String) -> String {
    value.replacingOccurrences(of: "'", with: "''")
}
