import Foundation
import CADCore
import CADIR
import CADTopology

public struct IGESExchange: Sendable {
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
        try ExactIGESWriter(
            resourceLimits: resourceLimits,
            tolerance: tolerance
        ).write(brep: brep, units: units, to: sink)
    }

    public func write(meshes: [BodyID: Mesh], units: UnitSystem = .meters, to sink: any ByteSink) throws {
        _ = meshes
        _ = units
        _ = sink
        throw KernelError(
            phase: .exchange,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message: "IGES export accepts exact B-rep only; mesh-to-IGES conversion is forbidden."
        )

    }

    public func `import`(_ source: any ByteSource) throws -> ImportedExchangeModel {
        try tolerance.validate()
        try resourceLimits.validate()
        let budget = ExchangeProcessingBudget(maximumDuration: resourceLimits.maximumProcessingDuration)
        return try source.withNoCopyData { data in
            try budget.check(format: .iges)
            guard data.count <= resourceLimits.maximumBytes else {
                throw KernelError(
                    phase: .exchange,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "IGES input exceeds the configured byte limit."
                )
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw ImportError.invalidData("IGES data is not UTF-8.")
            }
            return try importText(text, budget: budget)
        }
    }

    private func importText(
        _ text: String,
        budget: ExchangeProcessingBudget
    ) throws -> ImportedExchangeModel {
        try validateIGESResourceBudget(text, budget: budget)
        try budget.check(format: .iges)
        try validateIGESRecordTable(in: text)
        try budget.check(format: .iges)
        let recordCount = text.split(separator: "\n", omittingEmptySubsequences: true).count
        guard recordCount <= resourceLimits.maximumEntities else {
            throw KernelError(
                phase: .exchange,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "IGES input exceeds the configured entity limit."
            )
        }

        let unit = try igesLengthUnit(in: text)
        try budget.check(format: .iges)
        let brep = try ExactIGESReader(
            text: text,
            lengthUnit: unit,
            processingBudget: budget,
            tolerance: tolerance
        ).read()
        try budget.check(format: .iges)
        return ImportedExchangeModel(
            format: .iges,
            brep: brep,
            units: UnitSystem(length: unit, angle: .radian)
        )
    }

    private func validateIGESResourceBudget(
        _ text: String,
        budget: ExchangeProcessingBudget
    ) throws {
        let limits = resourceLimits
        let iterations = text.count
        guard iterations <= limits.maximumIterations else {
            throw KernelError(
                phase: .exchange,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "IGES parsing exceeded the configured iteration limit."
            )
        }
        var depth = 0
        for (index, character) in text.enumerated() {
            if index.isMultiple(of: 4_096) {
                try budget.check(format: .iges)
            }
            if character == "(" {
                depth += 1
                guard depth <= limits.maximumNesting else {
                    throw KernelError(
                        phase: .exchange,
                        code: .resourceLimitExceeded,
                        tolerance: tolerance,
                        message: "IGES nesting exceeded the configured limit."
                    )
                }
            } else if character == ")" {
                depth -= 1
                guard depth >= 0 else {
                    throw ImportError.invalidData("IGES exchange contains unbalanced parentheses.")
                }
            }
        }
    guard depth == 0 else {
        throw ImportError.invalidData("IGES exchange contains an unterminated tuple.")
    }
}

}

private func igesSupportedLengthUnit(for unit: LengthUnit) -> LengthUnit {
    switch unit {
    case .meter, .micrometer, .millimeter, .centimeter, .kilometer, .inch, .foot:
        unit
    }
}

private func igesGlobalParameterData(unit: LengthUnit) -> String {
    [
        "1H,",
        "1H;",
        "4HSWFT",
        "13Hswift-cad.igs",
        "9HSwift-CAD",
        "9HSwift-CAD",
        "32",
        "38",
        "6",
        "308",
        "15",
        "1.0",
        "2",
        "\(igesUnitFlag(for: unit))",
        "\(igesHollerith(igesUnitName(for: unit)))",
        "1",
        "0.001",
        "15H20260603.000000",
        "1.0E-6",
        "0.0",
        "\(igesHollerith("1amageek"))",
        "\(igesHollerith("Swift-CAD"))",
        "11",
        "0",
        "15H20260603.000000"
    ].joined(separator: ",") + ";"
}

private func igesUnitFlag(for unit: LengthUnit) -> Int {
    switch unit {
    case .inch:
        1
    case .millimeter:
        2
    case .foot:
        4
    case .meter:
        6
    case .kilometer:
        7
    case .micrometer:
        9
    case .centimeter:
        10
    }
}

private func igesUnitName(for unit: LengthUnit) -> String {
    switch unit {
    case .micrometer:
        "MICRON"
    case .meter:
        "M"
    case .kilometer:
        "KM"
    case .millimeter:
        "MM"
    case .centimeter:
        "CM"
    case .inch:
        "IN"
    case .foot:
        "FT"
    }
}

private func igesLengthUnit(in text: String) throws -> LengthUnit {
    let parameters = try igesGlobalParameters(in: text)
    guard !parameters.isEmpty else {
        throw ImportError.invalidData("Missing IGES Global section.")
    }
    guard parameters.count > 13 else {
        throw ImportError.invalidData("IGES global section is missing the unit flag.")
    }
    let unitFlagText = parameters[13].trimmingCharacters(in: .whitespacesAndNewlines)
    guard let unitFlag = Int(unitFlagText) else {
        throw ImportError.invalidData("IGES global unit flag is not an integer.")
    }
    guard let unit = igesLengthUnit(forFlag: unitFlag) else {
        throw ImportError.invalidData("Unsupported IGES global unit flag \(unitFlag).")
    }
    return unit
}

private func igesLengthUnit(forFlag flag: Int) -> LengthUnit? {
    switch flag {
    case 1:
        .inch
    case 2:
        .millimeter
    case 4:
        .foot
    case 6:
        .meter
    case 7:
        .kilometer
    case 9:
        .micrometer
    case 10:
        .centimeter
    default:
        nil
    }
}

private struct IGESRecord: Sendable {
    let content: String
    let section: Character
    let sequence: Int
}

private func validateIGESRecordTable(in text: String) throws {
    var lines = text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { rawLine -> String in
            if rawLine.last == "\r" {
                return String(rawLine.dropLast())
            }
            return String(rawLine)
        }
    while lines.last == "" {
        lines.removeLast()
    }
    guard !lines.isEmpty else {
        throw ImportError.invalidData("IGES record table is empty.")
    }

    let supportedSections: Set<Character> = ["S", "G", "D", "P", "T"]
    var records: [IGESRecord] = []
    for line in lines {
        let characters = Array(line)
        guard characters.count == 80 else {
            throw ImportError.invalidData("IGES records must be fixed-width 80 character records.")
        }
        let section = characters[72]
        guard supportedSections.contains(section) else {
            throw ImportError.invalidData("Unsupported IGES section \(section).")
        }
        let sequenceText = String(characters[73..<80]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sequence = Int(sequenceText), sequence > 0 else {
            throw ImportError.invalidData("IGES record sequence number is invalid.")
        }
        records.append(IGESRecord(content: String(characters[0..<72]), section: section, sequence: sequence))
    }

    guard let terminateRecord = records.last, terminateRecord.section == "T" else {
        throw ImportError.invalidData("IGES record table must terminate with a T record.")
    }
    guard records.filter({ $0.section == "T" }).count == 1, terminateRecord.sequence == 1 else {
        throw ImportError.invalidData("IGES record table must contain exactly one terminal T record.")
    }

    var counts: [Character: Int] = [:]
    var currentRank = -1
    let sectionRanks: [Character: Int] = ["S": 0, "G": 1, "D": 2, "P": 3, "T": 4]
    for record in records {
        guard let rank = sectionRanks[record.section] else {
            throw ImportError.invalidData("Unsupported IGES section \(record.section).")
        }
        guard rank >= currentRank else {
            throw ImportError.invalidData("IGES sections are out of order.")
        }
        currentRank = rank
        counts[record.section, default: 0] += 1
        guard record.sequence == counts[record.section] else {
            throw ImportError.invalidData("IGES section \(record.section) sequence numbers are not contiguous.")
        }
    }
    guard (counts["S"] ?? 0) > 0 else {
        throw ImportError.invalidData("Missing IGES Start section.")
    }
    guard (counts["G"] ?? 0) > 0 else {
        throw ImportError.invalidData("Missing IGES Global section.")
    }
    guard (counts["D"] ?? 0) > 0 else {
        throw ImportError.invalidData("Missing IGES Directory section.")
    }
    guard (counts["P"] ?? 0) > 0 else {
        throw ImportError.invalidData("Missing IGES Parameter section.")
    }

    let terminateCounts = try igesTerminateSectionCounts(in: terminateRecord.content)
    guard terminateCounts.start == (counts["S"] ?? 0),
          terminateCounts.global == (counts["G"] ?? 0),
          terminateCounts.directory == (counts["D"] ?? 0),
          terminateCounts.parameter == (counts["P"] ?? 0) else {
        throw ImportError.invalidData("IGES terminate section counts do not match the record table.")
    }
    try validateIGESDirectoryRecords(records)
}

private func igesTerminateSectionCounts(in content: String) throws -> (
    start: Int,
    global: Int,
    directory: Int,
    parameter: Int
) {
    let characters = Array(content)
    func count(marker: Character, offset: Int) throws -> Int {
        guard characters[offset] == marker else {
            throw ImportError.invalidData("IGES terminate record section count is malformed.")
        }
        let text = String(characters[(offset + 1)..<(offset + 8)]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(text), value >= 0 else {
            throw ImportError.invalidData("IGES terminate record section count is invalid.")
        }
        return value
    }

    let start = try count(marker: "S", offset: 0)
    let global = try count(marker: "G", offset: 8)
    let directory = try count(marker: "D", offset: 16)
    let parameter = try count(marker: "P", offset: 24)
    let trailing = String(characters[32..<72]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard trailing.isEmpty else {
        throw ImportError.invalidData("IGES terminate record contains trailing payload.")
    }
    return (start, global, directory, parameter)
}

private func validateIGESDirectoryRecords(_ records: [IGESRecord]) throws {
    let directoryRecords = records.filter { $0.section == "D" }
    guard !directoryRecords.isEmpty else {
        throw ImportError.invalidData("Missing IGES Directory section.")
    }
    guard directoryRecords.count.isMultiple(of: 2) else {
        throw ImportError.invalidData("IGES directory section must contain paired records.")
    }

    let parameterRecordCount = records.filter { $0.section == "P" }.count
    var referencedParameterSequences = Set<Int>()
    for index in stride(from: 0, to: directoryRecords.count, by: 2) {
        let first = directoryRecords[index]
        let second = directoryRecords[index + 1]
        let firstEntityType = try igesDirectoryIntegerField(in: first.content, index: 0)
        let secondEntityType = try igesDirectoryIntegerField(in: second.content, index: 0)
        guard firstEntityType == secondEntityType else {
            throw ImportError.invalidData("IGES directory entity type pair is inconsistent.")
        }
        let supportedEntityTypes: Set<Int> = [
            100, 104, 110, 116, 123, 124, 126, 128, 140, 142,
            186, 190, 192, 194, 196, 198,
            402, 502, 504, 508, 510, 514,
        ]
        guard supportedEntityTypes.contains(firstEntityType) else {
            throw ImportError.invalidData("Unsupported IGES directory entity type \(firstEntityType).")
        }

        let parameterPointer = try igesDirectoryIntegerField(in: first.content, index: 1)
        let parameterLineCount = try igesDirectoryIntegerField(in: second.content, index: 3)
        guard parameterPointer > 0, parameterLineCount > 0 else {
            throw ImportError.invalidData("IGES directory parameter pointer is invalid.")
        }
        guard parameterPointer + parameterLineCount - 1 <= parameterRecordCount else {
            throw ImportError.invalidData("IGES directory parameter pointer exceeds the parameter section.")
        }
        for sequence in parameterPointer..<(parameterPointer + parameterLineCount) {
            guard referencedParameterSequences.insert(sequence).inserted else {
                throw ImportError.invalidData("IGES directory references a parameter record more than once.")
            }
        }
    }

    guard referencedParameterSequences.count == parameterRecordCount else {
        throw ImportError.invalidData("IGES parameter records are not fully covered by the directory section.")
    }
}

private func igesDirectoryIntegerField(in content: String, index: Int) throws -> Int {
    let characters = Array(content)
    let start = index * 8
    let end = start + 8
    guard start >= 0, end <= characters.count else {
        throw ImportError.invalidData("IGES directory field index is out of range.")
    }
    let text = String(characters[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Int(text) else {
        throw ImportError.invalidData("IGES directory field is not an integer.")
    }
    return value
}

private func igesGlobalParameters(in text: String) throws -> [String] {
    let globalText = text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .filter { line in
            let characters = Array(line)
            return characters.count >= 73 && characters[72] == "G"
        }
        .map { line in
            String(line.prefix(72)).trimmingCharacters(in: .whitespaces)
        }
        .joined()
    guard !globalText.isEmpty else {
        return []
    }

    var parameters: [String] = []
    var index = globalText.startIndex
    while index < globalText.endIndex {
        skipIGESWhitespace(in: globalText, index: &index)
        guard index < globalText.endIndex else {
            break
        }
        if globalText[index] == ";" {
            break
        }

        let parameter = try readIGESGlobalParameter(in: globalText, index: &index)
        parameters.append(parameter)
        skipIGESWhitespace(in: globalText, index: &index)
        if index < globalText.endIndex, globalText[index] == "," {
            index = globalText.index(after: index)
            continue
        }
        if index < globalText.endIndex, globalText[index] == ";" {
            break
        }
        if index < globalText.endIndex {
            throw ImportError.invalidData("IGES global parameter list is malformed.")
        }
    }
    return parameters
}

private func readIGESGlobalParameter(in text: String, index: inout String.Index) throws -> String {
    let start = index
    var cursor = index
    while cursor < text.endIndex, text[cursor].isNumber {
        cursor = text.index(after: cursor)
    }
    if cursor > start,
       cursor < text.endIndex,
       text[cursor] == "H",
       let count = Int(text[start..<cursor]) {
        var end = text.index(after: cursor)
        for _ in 0..<count {
            guard end < text.endIndex else {
                throw ImportError.invalidData("IGES Hollerith global parameter is truncated.")
            }
            end = text.index(after: end)
        }
        let parameter = String(text[start..<end])
        index = end
        return parameter
    }

    while index < text.endIndex,
          text[index] != ",",
          text[index] != ";" {
        index = text.index(after: index)
    }
    return String(text[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func skipIGESWhitespace(in text: String, index: inout String.Index) {
    while index < text.endIndex, text[index].isWhitespace {
        index = text.index(after: index)
    }
}

private func igesLineParameterData(start: Point3D, end: Point3D, unit: LengthUnit) throws -> String {
    [
        "110",
        stepNumber(try checkedExportUnitValue(
            unit.fromInternal(start.x),
            formatName: "IGES",
            component: "line.start.x"
        )),
        stepNumber(try checkedExportUnitValue(
            unit.fromInternal(start.y),
            formatName: "IGES",
            component: "line.start.y"
        )),
        stepNumber(try checkedExportUnitValue(
            unit.fromInternal(start.z),
            formatName: "IGES",
            component: "line.start.z"
        )),
        stepNumber(try checkedExportUnitValue(
            unit.fromInternal(end.x),
            formatName: "IGES",
            component: "line.end.x"
        )),
        stepNumber(try checkedExportUnitValue(
            unit.fromInternal(end.y),
            formatName: "IGES",
            component: "line.end.y"
        )),
        stepNumber(try checkedExportUnitValue(
            unit.fromInternal(end.z),
            formatName: "IGES",
            component: "line.end.z"
        ))
    ].joined(separator: ",") + ";"
}

private func igesDirectoryRecords(
    entityType: Int,
    parameterPointer: Int,
    parameterLineCount: Int,
    formNumber: Int,
    label: String,
    entityIndex: Int
) -> [String] {
    let firstSequence = entityIndex * 2 - 1
    let secondSequence = entityIndex * 2
    let first = [
        igesIntegerField(entityType),
        igesIntegerField(parameterPointer),
        igesIntegerField(0),
        igesIntegerField(0),
        igesIntegerField(0),
        igesIntegerField(0),
        igesIntegerField(0),
        igesIntegerField(0),
        igesIntegerField(0)
    ].joined()
    let second = [
        igesIntegerField(entityType),
        igesIntegerField(0),
        igesIntegerField(0),
        igesIntegerField(parameterLineCount),
        igesIntegerField(formNumber),
        igesIntegerField(0),
        igesIntegerField(0),
        igesTextField(label),
        igesIntegerField(entityIndex)
    ].joined()
    return [
        igesSectionRecord(first, section: "D", sequence: firstSequence),
        igesSectionRecord(second, section: "D", sequence: secondSequence)
    ]
}

private func igesParameterRecords(data: String, directoryPointer: Int, startSequence: Int) -> [String] {
    let characters = Array(data)
    var records: [String] = []
    var offset = 0
    var sequence = startSequence
    while offset < characters.count {
        let end = min(offset + 64, characters.count)
        let chunk = String(characters[offset..<end])
        let content = chunk.padding(toLength: 64, withPad: " ", startingAt: 0)
            + igesIntegerField(directoryPointer)
        records.append(igesSectionRecord(content, section: "P", sequence: sequence))
        offset = end
        sequence += 1
    }
    return records
}

private func igesParameterRecordCount(data: String) -> Int {
    max(1, (data.count + 63) / 64)
}

private func writeIGESRecord(_ record: String, to sink: any ByteSink, isFirst: inout Bool) throws {
    if isFirst {
        isFirst = false
    } else {
        try sink.writeUTF8("\n")
    }
    try sink.writeUTF8(record)
}

private func igesSectionRecord(_ content: String, section: Character, sequence: Int) -> String {
    let body = String(content.prefix(72)).padding(toLength: 72, withPad: " ", startingAt: 0)
    return body + String(section) + String(format: "%7d", locale: Locale(identifier: "en_US_POSIX"), sequence)
}

private func igesSectionRecords(_ content: String, section: Character) -> [String] {
    let characters = Array(content)
    guard !characters.isEmpty else {
        return [igesSectionRecord("", section: section, sequence: 1)]
    }
    var records: [String] = []
    var offset = 0
    var sequence = 1
    while offset < characters.count {
        let end = min(offset + 72, characters.count)
        records.append(igesSectionRecord(String(characters[offset..<end]), section: section, sequence: sequence))
        offset = end
        sequence += 1
    }
    return records
}

private func igesTerminateRecord(startCount: Int, globalCount: Int, directoryCount: Int, parameterCount: Int) -> String {
    let content = "S\(igesIntegerField(startCount).dropFirst())G\(igesIntegerField(globalCount).dropFirst())D\(igesIntegerField(directoryCount).dropFirst())P\(igesIntegerField(parameterCount).dropFirst())"
    return igesSectionRecord(content, section: "T", sequence: 1)
}

private func igesIntegerField(_ value: Int) -> String {
    String(format: "%8d", locale: Locale(identifier: "en_US_POSIX"), value)
}

private func igesTextField(_ value: String) -> String {
    String(value.prefix(8)).padding(toLength: 8, withPad: " ", startingAt: 0)
}

private func igesHollerith(_ value: String) -> String {
    "\(value.count)H\(value)"
}

private func igesLineSegments(in text: String, unit: LengthUnit) throws -> [(start: Point3D, end: Point3D)] {
    let parameterText = text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .filter { line in
            let characters = Array(line)
            return characters.count >= 73 && characters[72] == "P"
        }
        .map { line in
            String(line.prefix(64)).trimmingCharacters(in: .whitespaces)
        }
        .joined()

    let records = try parseIGESParameterRecords(in: parameterText)
    var lines: [(start: Point3D, end: Point3D)] = []
    for record in records {
        guard record.entityType == 110 else {
            throw ImportError.invalidData("Unsupported IGES entity type \(record.entityType).")
        }
        guard let payload = record.payload else {
            throw ImportError.invalidData("IGES type 110 line entity is malformed.")
        }
        let values = try numericValues(from: payload, expectedCount: 6, label: "IGES line")
        lines.append((
            start: Point3D(x: unit.toInternal(values[0]), y: unit.toInternal(values[1]), z: unit.toInternal(values[2])),
            end: Point3D(x: unit.toInternal(values[3]), y: unit.toInternal(values[4]), z: unit.toInternal(values[5]))
        ))
    }
    return lines
}

private struct IGESParameterRecord: Sendable {
    let entityType: Int
    let payload: String?
}

private func parseIGESParameterRecords(in text: String) throws -> [IGESParameterRecord] {
    let rawRecords = text.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
    if let trailing = rawRecords.last?.trimmingCharacters(in: .whitespacesAndNewlines),
       !trailing.isEmpty {
        throw ImportError.invalidData("IGES parameter record is unterminated.")
    }
    return try rawRecords.compactMap { rawRecord in
        let trimmed = rawRecord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let delimiter = trimmed.firstIndex(of: ",")
        let typeSubstring = delimiter.map { trimmed[..<$0] } ?? trimmed[...]
        let typeText = String(typeSubstring).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let entityType = Int(typeText) else {
            throw ImportError.invalidData("IGES parameter record has a non-integer entity type.")
        }
        let payload = delimiter.map { String(trimmed[trimmed.index(after: $0)...]) }
        return IGESParameterRecord(entityType: entityType, payload: payload)
    }
}
