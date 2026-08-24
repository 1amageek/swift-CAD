import Foundation
import CADCore
import CADIR
import CADTopology

public struct STEPExchange: Sendable {
    private let resourceLimits: ExchangeResourceLimits
    private let tolerance: ModelingTolerance

    public init(
        tolerance: ModelingTolerance,
        resourceLimits: ExchangeResourceLimits = .standard
    ) {
        self.tolerance = tolerance
        self.resourceLimits = resourceLimits
    }

    public func write(
        brep: BRepModel,
        units: UnitSystem = .meters,
        to sink: any ByteSink
    ) throws {
        try units.validate()
        try tolerance.validate()
        try resourceLimits.validate()
        try brep.validate(level: .exact, tolerance: tolerance)
        try ExactSTEPWriter(
            resourceLimits: resourceLimits,
            tolerance: tolerance
        ).write(
            brep: brep,
            units: units,
            to: sink
        )
    }

    public func write(meshes: [BodyID: Mesh], units: UnitSystem = .meters, to sink: any ByteSink) throws {
        _ = meshes
        _ = units
        _ = sink
        throw KernelError(
            phase: .exchange,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message: "STEP export accepts exact B-rep only; mesh-to-STEP conversion is forbidden."
        )
    }

    public func `import`(_ source: any ByteSource) throws -> ImportedExchangeModel {
        try tolerance.validate()
        try resourceLimits.validate()
        let budget = ExchangeProcessingBudget(maximumDuration: resourceLimits.maximumProcessingDuration)
        return try source.withNoCopyData { data in
            try budget.check(format: .step)
            guard data.count <= resourceLimits.maximumBytes else {
                throw KernelError(
                    phase: .exchange,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "STEP input exceeds the configured byte limit."
                )
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw ImportError.invalidData("STEP data is not UTF-8.")
            }
            return try importText(text, budget: budget)
        }
    }

    private func importText(
        _ text: String,
        budget: ExchangeProcessingBudget
    ) throws -> ImportedExchangeModel {
        try validateSTEPResourceBudget(text, budget: budget)
        try budget.check(format: .step)
        try validateSTEPExchangeEnvelope(in: text)

        let dataSections = try stepDataSections(in: text)
        try budget.check(format: .step)
        try rejectSTEPEntityMarkersOutsideDataSections(in: text, dataRanges: dataSections.map(\.contentRange))
        guard !dataSections.isEmpty else {
            throw ImportError.invalidData("Missing STEP DATA section.")
        }
        let entities = try stepEntities(in: dataSections.map(\.content).joined(separator: "\n"))
        try budget.check(format: .step)
        guard entities.count <= resourceLimits.maximumEntities else {
            throw KernelError(
                phase: .exchange,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "STEP input exceeds the configured entity limit."
            )
        }
        try validateSupportedSTEPEntities(entities)
        try budget.check(format: .step)
        if entities.values.contains(where: { $0.hasPrefix("TRIANGULATED_FACE_SET") }) {
            throw KernelError(
                phase: .exchange,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Tessellated STEP is a mesh exchange and cannot be imported as exact CAD geometry."
            )
        }
        let lengthUnit = try stepLengthUnit(in: entities)
        try budget.check(format: .step)
        let brep = try ExactSTEPReader(
            entities: entities,
            lengthUnit: lengthUnit,
            processingBudget: budget,
            tolerance: tolerance
        ).read()
        try budget.check(format: .step)
        return ImportedExchangeModel(
            format: .step,
            brep: brep,
            units: UnitSystem(length: lengthUnit, angle: .radian)
        )
    }

    private func validateSTEPResourceBudget(
        _ text: String,
        budget: ExchangeProcessingBudget
    ) throws {
        let limits = resourceLimits
        var depth = 0
        var iterations = 0
        var inString = false
        var cursor = text.startIndex
        while cursor < text.endIndex {
            iterations += 1
            if iterations.isMultiple(of: 4_096) {
                try budget.check(format: .step)
            }
            guard iterations <= limits.maximumIterations else {
                throw KernelError(
                    phase: .exchange,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "STEP parsing exceeded the configured iteration limit."
                )
            }
            let character = text[cursor]
            if character == "'" {
                let next = text.index(after: cursor)
                if next < text.endIndex, text[next] == "'" {
                    cursor = text.index(after: next)
                    continue
                }
                inString.toggle()
            } else if !inString {
                if character == "(" {
                    depth += 1
                    guard depth <= limits.maximumNesting else {
                        throw KernelError(
                            phase: .exchange,
                            code: .resourceLimitExceeded,
                            tolerance: tolerance,
                            message: "STEP nesting exceeded the configured limit."
                        )
                    }
                } else if character == ")" {
                    depth -= 1
                    guard depth >= 0 else {
                        throw ImportError.invalidData("STEP exchange contains unbalanced parentheses.")
                    }
                }
            }
            cursor = text.index(after: cursor)
        }
    guard !inString, depth == 0 else {
        throw ImportError.invalidData("STEP exchange contains an unterminated string or tuple.")
    }
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
        "CARTESIAN_POINT(",
        "VERTEX_POINT(",
        "DIRECTION(",
        "VECTOR(",
        "LINE(",
        "CIRCLE(",
        "ELLIPSE(",
        "HYPERBOLA(",
        "PARABOLA(",
        "TRIMMED_CURVE(",
        "PCURVE(",
        "SURFACE_CURVE(",
        "DEFINITIONAL_REPRESENTATION(",
        "EDGE_CURVE(",
        "ORIENTED_EDGE(",
        "EDGE_LOOP(",
        "FACE_OUTER_BOUND(",
        "FACE_BOUND(",
        "AXIS2_PLACEMENT_2D(",
        "AXIS2_PLACEMENT_3D(",
        "PLANE(",
        "CYLINDRICAL_SURFACE(",
        "CONICAL_SURFACE(",
        "SPHERICAL_SURFACE(",
        "TOROIDAL_SURFACE(",
        "OFFSET_SURFACE(",
        "ADVANCED_FACE(",
        "OPEN_SHELL(",
        "CLOSED_SHELL(",
        "ORIENTED_CLOSED_SHELL(",
        "MANIFOLD_SOLID_BREP(",
        "BREP_WITH_VOIDS(",
        "SHELL_BASED_SURFACE_MODEL(",
        "SHAPE_REPRESENTATION(",
        "UNCERTAINTY_MEASURE_WITH_UNIT(",
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
    if syntax.contains("B_SPLINE_CURVE("),
       syntax.contains("B_SPLINE_CURVE_WITH_KNOTS("),
       syntax.contains("RATIONAL_B_SPLINE_CURVE("),
       syntax.contains("REPRESENTATION_ITEM(") {
        return true
    }
    if syntax.contains("B_SPLINE_SURFACE("),
       syntax.contains("B_SPLINE_SURFACE_WITH_KNOTS("),
       syntax.contains("RATIONAL_B_SPLINE_SURFACE("),
       syntax.contains("REPRESENTATION_ITEM(") {
        return true
    }
    if syntax.contains("GEOMETRIC_REPRESENTATION_CONTEXT("),
       syntax.contains("GLOBAL_UNIT_ASSIGNED_CONTEXT(("),
       syntax.contains("REPRESENTATION_CONTEXT(") {
        return true
    }
    if syntax.contains("GEOMETRIC_REPRESENTATION_CONTEXT(2)"),
       syntax.contains("PARAMETRIC_REPRESENTATION_CONTEXT()"),
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
