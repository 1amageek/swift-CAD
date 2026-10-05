import CADCore

/// Removes unsupported information and its complete reverse dependency closure.
struct STEPPartialImportPlanner {
    struct Result {
        let entities: [Int: String]
        let report: ExchangePreservationReport
        let consumedWork: Int
        let consumedEntities: Int
        let consumedBytes: Int
    }
    let limits: ExchangeResourceLimits
    let budget: ExchangeProcessingBudget
    func plan(entities: [Int: String], accepting domains: Set<ExchangeInformationDomain>,
              isSupported: (String) -> Bool) throws -> Result {
        var accounting = try ExchangeResourceAccountant(limits: limits, format: .step)
        try accounting.recordEntities(entities.count)
        // Admit typed owner slots before keys, indexes and pending storage are created.
        let stride = MemoryLayout<Int>.stride * 4 + MemoryLayout<(Int, String)>.stride
            + MemoryLayout<(Int, ExchangeInformationLoss.Reason)>.stride
        let storage = entities.count.multipliedReportingOverflow(by: stride)
        guard !storage.overflow else { throw exchangeResourceLimitError(format: .step, detail: "partial source index storage overflow") }
        try accounting.recordBytes(storage.partialValue)
        let syntax = STEPAssemblySyntax(entities: entities)
        var reverse: [Int: [Int]] = [:], names: [Int: String] = [:], discarded = Set<Int>(), pending: [Int] = []
        var reasons: [Int: ExchangeInformationLoss.Reason] = [:]
        for id in entities.keys.sorted() {
            try budget.check(format: .step)
            guard let value = entities[id] else { throw ImportError.missingRequiredEntity("STEP original source record.") }
            try accounting.recordBytes(value.utf8.count)
            try accounting.recordIterations(value.utf8.count + 1)
            let name = try syntax.name(id)
            try accounting.recordBytes(name.utf8.count)
            names[id] = name
            try STEPMetadataReferenceScanner.visitReferences(in: value) { reference in
                try budget.check(format: .step)
                try accounting.recordIterations(); try accounting.recordEntities()
                try accounting.recordBytes(MemoryLayout<Int>.stride + MemoryLayout<(Int, [Int])>.stride)
                guard entities[reference] != nil else { throw ExchangePreservationError.invalidReference(entity: id, missing: reference) }
                reverse[reference, default: []].append(id)
            }
            if !isSupported(value) {
                discarded.insert(id); pending.append(id); reasons[id] = .unsupportedEntity
            }
        }
        while let id = pending.popLast() {
            try budget.check(format: .step)
            for dependent in reverse[id] ?? [] {
                try accounting.recordIterations()
                if discarded.insert(dependent).inserted { pending.append(dependent); reasons[dependent] = .dependentOnDiscardedEntity }
            }
        }
        var losses: [ExchangeInformationLoss] = []
        for id in discarded.sorted() {
            try accounting.recordIterations()
            let reason = reasons[id] ?? .dependentOnDiscardedEntity
            try accounting.recordEntities()
            try accounting.recordBytes(MemoryLayout<ExchangeInformationLoss>.stride)
            losses.append(ExchangeInformationLoss(domain: reason == .unsupportedEntity ? .unknownSemantics : domain(names[id] ?? ""),
                reason: reason, entityID: id, entityName: names[id], originalRecord: entities[id],
                description: reason == .unsupportedEntity ? "Unsupported original STEP entity was explicitly discarded." : "Original STEP entity depends on discarded information."))
        }
        let report = ExchangePreservationReport(losses: losses)
        guard report.lostDomains.isSubset(of: domains) else { throw ExchangePreservationError.unacceptedLoss(report) }
        var retained: [Int: String] = [:]
        for (id, entity) in entities where !discarded.contains(id) {
            try budget.check(format: .step); try accounting.recordIterations(); try accounting.recordEntities()
            try accounting.recordBytes(MemoryLayout<(Int, String)>.stride)
            retained[id] = entity
        }
        guard !retained.isEmpty else { throw ExchangePreservationError.emptyRetainedSource }
        return Result(entities: retained, report: report, consumedWork: accounting.iterationCount,
            consumedEntities: accounting.entityCount, consumedBytes: accounting.byteCount)
    }
    private func domain(_ name: String) -> ExchangeInformationDomain {
        if ["GROUP", "APPLIED_GROUP_ASSIGNMENT", "GEOMETRIC_SET", "GEOMETRIC_CURVE_SET"].contains(name) { return .independentShapes }
        if name.contains("CAMERA") || name == "VIEW_VOLUME" || name == "PLANAR_BOX" { return .savedViews }
        if name == "AREA_MEASURE_WITH_UNIT" || name == "VOLUME_MEASURE_WITH_UNIT" { return .validationProperties }
        if STEPMetadataNames.simpleNames.contains(name) { return .manufacturingInformation }
        if name.contains("UNIT") || name.contains("CONTEXT") { return .units }
        if name.contains("STYLE") || name.contains("COLOUR") || name.contains("LAYER") { return .appearance }
        if name.contains("MATERIAL") || name.contains("PROPERTY") { return .physicalProperties }
        if name.contains("USAGE") || name.contains("MAPPED") || name.contains("TRANSFORMATION") { return .placement }
        if name.contains("SHELL") || name.contains("BOUND") || name.contains("LOOP") || name.contains("FACE") || name.contains("BREP") || name.contains("EDGE") || name.contains("VERTEX") { return .topology }
        if name.contains("CURVE") || name.contains("SURFACE") || name == "CARTESIAN_POINT" || name == "DIRECTION" { return .geometry }
        return .unknownSemantics
    }
}
