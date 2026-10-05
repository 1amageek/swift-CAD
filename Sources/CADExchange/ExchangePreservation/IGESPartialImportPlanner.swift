import Foundation
import CADCore

struct IGESPartialImportPlanner {
    struct Result {
        let discarded: Set<Int>
        let report: ExchangePreservationReport
        let remainingLimits: ExchangeResourceLimits
    }
    let limits: ExchangeResourceLimits
    let budget: ExchangeProcessingBudget
    private let types: Set<Int> = [100, 104, 110, 116, 123, 124, 126, 128, 140, 142, 186, 190, 192, 194, 196, 198, 308, 408, 402, 502, 504, 508, 510, 514]

    func plan(entities: [Int: ExactIGESReader.Entity], policy: ExchangeImportPolicy) throws -> Result {
        var accounting = try ExchangeResourceAccountant(limits: limits, format: .iges)
        try accounting.recordEntities(entities.count)
        let ownerStride = MemoryLayout<Int>.stride * 3 + MemoryLayout<(Int, [Int])>.stride
        let ownerBytes = entities.count.multipliedReportingOverflow(by: ownerStride)
        guard !ownerBytes.overflow else { throw exchangeResourceLimitError(format: .iges, detail: "partial source index storage overflow") }
        try accounting.recordBytes(ownerBytes.partialValue)
        var reverse: [Int: [Int]] = [:], discarded = Set<Int>(), pending: [Int] = []
        var losses: [ExchangeInformationLoss] = []
        for id in entities.keys.sorted() {
            try budget.check(format: .iges)
            guard let entity = entities[id] else { throw ImportError.missingRequiredEntity("Original IGES source record.") }
            try accounting.recordIterations(entity.originalRecord.utf8.count + entity.parameters.count)
            try accounting.recordBytes(entity.originalRecord.utf8.count)
            try accounting.recordBytes(6 * MemoryLayout<Substring>.stride + 16 * (MemoryLayout<String>.stride + 8))
            let supported = supports(entity)
            if !supported { discarded.insert(id); pending.append(id) }
            try references(entity) { pointer in
                try budget.check(format: .iges)
                try accounting.recordEntities(); try accounting.recordIterations()
                try accounting.recordBytes(MemoryLayout<Int>.stride + MemoryLayout<(Int, [Int])>.stride)
                guard entities[pointer] != nil else { throw ExchangePreservationError.invalidReference(entity: id, missing: pointer) }
                reverse[pointer, default: []].append(id)
            }
            try directoryReferences(entity, entityID: id, entities: entities) { pointer in
                try budget.check(format: .iges)
                try accounting.recordEntities(); try accounting.recordIterations()
                try accounting.recordBytes(MemoryLayout<Int>.stride + MemoryLayout<(Int, [Int])>.stride)
                reverse[pointer, default: []].append(id)
            }
            var metadataDomains = try directoryLosses(entity)
            if !entity.propertyPointers.isEmpty { metadataDomains.insert(.unknownSemantics) }
            for pointer in entity.associationPointers {
                try accounting.recordIterations()
                if let target = entities[pointer], !(target.type == 402 && [1, 7, 14, 15].contains(target.form)) {
                    metadataDomains.insert(.unknownSemantics)
                }
            }
            for domain in metadataDomains.sorted(by: { $0.rawValue < $1.rawValue }) {
                try accounting.recordEntities(); try accounting.recordBytes(MemoryLayout<ExchangeInformationLoss>.stride)
                losses.append(.init(domain: domain, reason: .unrepresentableSource, entityID: id, entityName: String(entity.type),
                    originalRecord: entity.originalRecord, description: "Original IGES metadata has no source value owner in this producer."))
            }
        }
        while let id = pending.popLast() {
            try budget.check(format: .iges)
            for dependent in reverse[id] ?? [] {
                try accounting.recordIterations()
                if discarded.insert(dependent).inserted { pending.append(dependent) }
            }
        }
        for id in discarded.sorted() {
            guard let entity = entities[id] else { throw ImportError.missingRequiredEntity("Discarded original IGES record.") }
            let unsupported = !supports(entity)
            let domain: ExchangeInformationDomain = unsupported ? .unknownSemantics : ([502,504,508,510,514,186].contains(entity.type) ? .topology : ([308,402].contains(entity.type) ? .independentShapes : (entity.type == 408 ? .placement : .geometry)))
            try budget.check(format: .iges); try accounting.recordEntities()
            try accounting.recordBytes(MemoryLayout<ExchangeInformationLoss>.stride)
            losses.append(.init(domain: domain, reason: unsupported ? .unsupportedEntity : .dependentOnDiscardedEntity,
                entityID: id, entityName: String(entity.type), originalRecord: entity.originalRecord,
                description: unsupported ? "Unsupported original IGES entity." : "Original entity depends on discarded source information."))
        }
        try accounting.recordIterations(losses.count)
        if case .allowPartial = policy {
            let retainedCount = entities.count - discarded.count
            let bytes = retainedCount.multipliedReportingOverflow(by: MemoryLayout<(Int, ExactIGESReader.Entity)>.stride)
            guard !bytes.overflow else { throw exchangeResourceLimitError(format: .iges, detail: "retained source storage overflow") }
            try accounting.recordEntities(retainedCount); try accounting.recordBytes(bytes.partialValue)
        }
        let report = ExchangePreservationReport(losses: losses)
        switch policy {
        case .strict: guard report.isComplete else { throw ExchangePreservationError.unacceptedLoss(report) }
        case .allowPartial(let accepting): guard report.lostDomains.isSubset(of: accepting) else { throw ExchangePreservationError.unacceptedLoss(report) }
        }
        let remaining = ExchangeResourceLimits(maximumBytes: limits.maximumBytes - accounting.byteCount,
            maximumEntities: limits.maximumEntities - accounting.entityCount, maximumNesting: limits.maximumNesting,
            maximumIterations: limits.maximumIterations - accounting.iterationCount, maximumProcessingDuration: limits.maximumProcessingDuration, maximumCurveSubdivisionDepth: limits.maximumCurveSubdivisionDepth, maximumAlgebraicDepth: limits.maximumAlgebraicDepth)
        try remaining.validate()
        return .init(discarded: discarded, report: report, remainingLimits: remaining)
    }

    private func supports(_ entity: ExactIGESReader.Entity) -> Bool {
        types.contains(entity.type) && (entity.type != 402 || [1, 7, 14, 15].contains(entity.form))
    }

    private func directoryLosses(_ entity: ExactIGESReader.Entity) throws -> Set<ExchangeInformationDomain> {
        let (first, second) = try directoryPair(entity)
        var domains = Set<ExchangeInformationDomain>()
        for index in [3,4,5,7] { if try directoryField(first,index) != 0 { domains.insert(.appearance) } }
        for index in [1,2] { if try directoryField(second,index) != 0 { domains.insert(.appearance) } }
        if try directoryField(first,2) != 0 { domains.insert(.unknownSemantics) }
        if try directoryField(second,8) != 0 { domains.insert(.independentShapes) }
        let blank = try directoryField(first, 8) / 1_000_000
        guard blank == 0 || blank == 1 else { throw ImportError.invalidData("Invalid original IGES blank status.") }
        if blank == 1 { domains.insert(.appearance) }
        return domains
    }

    private func directoryPair(_ entity: ExactIGESReader.Entity) throws -> (Substring, Substring) {
        let lines = entity.originalRecord.split(separator: "\n", maxSplits: 2)
        guard lines.count >= 2 else { throw ImportError.invalidData("Original IGES directory pair is absent.") }
        return (lines[0], lines[1])
    }
    private func directoryField(_ line: Substring, _ index: Int) throws -> Int {
        guard line.utf8.count == 80, line.utf8.allSatisfy({ $0 < 128 }), (0...8).contains(index) else {
            throw ImportError.invalidData("Malformed original IGES directory width or encoding.")
        }
        let start = line.index(line.startIndex, offsetBy: index * 8), end = line.index(start, offsetBy: 8)
        let token = line[start..<end].trimmingCharacters(in: .whitespaces)
        if token.isEmpty { return 0 }
        guard let value = Int(token) else { throw ImportError.invalidData("Malformed original IGES directory metadata.") }
        return value
    }
    private func directoryReferences(_ entity: ExactIGESReader.Entity, entityID: Int, entities: [Int: ExactIGESReader.Entity],
        visit: (Int) throws -> Void) throws {
        let (first, second) = try directoryPair(entity)
        func pointer(_ value: Int, negative: Bool, requiredType: Int? = nil, requiredForms: Set<Int>? = nil) throws {
            if negative { guard value < 0 else { return } }
            else { guard value >= 0 else { throw ImportError.invalidData("Negative original IGES directory pointer.") }; if value == 0 { return } }
            guard value != Int.min else { throw ImportError.invalidData("Original IGES pointer absolute value overflows.") }
            let id = negative ? -value : value
            guard id > 0, id % 2 == 1 else { throw ImportError.invalidData("Malformed original IGES directory reference.") }
            guard let target = entities[id] else { throw ExchangePreservationError.invalidReference(entity: entityID, missing: id) }
            if let requiredType, target.type != requiredType { throw ImportError.invalidData("Original IGES directory pointer has the wrong target family.") }
            if let requiredForms, !requiredForms.contains(target.form) { throw ImportError.invalidData("Original IGES directory pointer has the wrong target form.") }
            try visit(id)
        }
        try pointer(directoryField(first, 2), negative: true)
        try pointer(directoryField(first, 3), negative: true, requiredType: 304)
        try pointer(directoryField(first, 4), negative: true, requiredType: 406, requiredForms: [1])
        try pointer(directoryField(second, 2), negative: true, requiredType: 314)
        let view = try directoryField(first, 5)
        if view != 0 {
            try pointer(view, negative: false)
            guard let target = entities[view], target.type == 410 || target.type == 402 && [3, 4, 19].contains(target.form) else {
                throw ImportError.invalidData("Original IGES view pointer has the wrong target family/form.")
            }
        }
        try pointer(directoryField(first, 7), negative: false, requiredType: 402, requiredForms: [5])
    }

    private func references(_ entity: ExactIGESReader.Entity, visit: (Int) throws -> Void) throws {
        let p = entity.parameters
        func integer(_ index: Int) throws -> Int {
            guard p.indices.contains(index), let value = Int(p[index]) else { throw ImportError.invalidData("Malformed IGES pointer-bearing entity grammar.") }
            return value
        }
        func count(_ index: Int, base: Int, stride: Int) throws -> Int {
            let value = try integer(index), multiplied = value.multipliedReportingOverflow(by: stride)
            let total = multiplied.partialValue.addingReportingOverflow(base)
            guard value >= 0, !multiplied.overflow, !total.overflow, total.partialValue == p.count else { throw ImportError.invalidData("Inconsistent IGES entity reference count.") }
            return value
        }
        func append(_ index: Int, nullable: Bool = false) throws {
            let pointer = try integer(index)
            if pointer == 0, nullable { return }
            guard pointer > 0, pointer % 2 == 1 else { throw ImportError.invalidData("Malformed original IGES directory reference.") }
            try visit(pointer)
        }
        if entity.transformationPointer != 0 {
            guard entity.transformationPointer > 0, entity.transformationPointer % 2 == 1 else { throw ImportError.invalidData("Malformed original IGES transform reference.") }
            try visit(entity.transformationPointer)
        }
        for pointer in entity.associationPointers { try visit(pointer) }
        for pointer in entity.propertyPointers { try visit(pointer) }
        switch entity.type {
        case 140: try append(5)
        case 142: for index in [2,3,4] { try append(index, nullable: index == 3 || index == 4) }
        case 190: for index in [1,2,3] { try append(index) }
        case 192: for index in [1,2,4] { try append(index) }
        case 196: for index in [1,3,4] { try append(index) }
        case 194,198: for index in [1,2,5] { try append(index) }
        case 408: try append(1)
        case 308: for index in 0..<(try count(3,base:4,stride:1)) { try append(index+4) }
        case 402:
            if [1, 7, 14, 15].contains(entity.form) { for index in 0..<(try count(1,base:2,stride:1)) { try append(index+2) } }
        case 186:
            try append(1)
            for index in 0..<(try count(3,base:4,stride:2)) { try append(index*2+4) }
        case 514: for index in 0..<(try count(1,base:2,stride:2)) { try append(index*2+2) }
        case 510:
            try append(1)
            for index in 0..<(try count(2,base:4,stride:1)) { try append(index+4) }
        case 504: for index in 0..<(try count(1,base:2,stride:5)) { for offset in [0,1,3] { try append(index*5+2+offset) } }
        case 508:
            let n = try integer(1)
            guard n >= 0, n <= p.count / 5 else { throw ImportError.invalidData("Malformed IGES loop reference count.") }
            var cursor = 2
            for _ in 0..<n {
                try append(cursor+1)
                let count = try integer(cursor+4)
                guard count >= 0, count <= (p.count-cursor-5)/2 else { throw ImportError.invalidData("Truncated IGES loop parameter references.") }
                cursor += 5
                for _ in 0..<count { try append(cursor+1); cursor += 2 }
            }
            guard cursor == p.count else { throw ImportError.invalidData("Trailing IGES loop references.") }
        default: break
        }
    }
}
