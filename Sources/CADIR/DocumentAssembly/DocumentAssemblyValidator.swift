import HashTreeCollections
import CADCore
import CADGeometry

public struct DocumentAssemblyValidator: DocumentAssemblyValidating {
    public init() {}
    public func expandedOccurrences(of assembly: DocumentAssembly, in graph: DesignGraph,
                                    tolerance: ModelingTolerance,
                                    limits: AssemblyResourceLimits = .standard) throws -> [ExpandedAssemblyOccurrence] {
        try expand(assembly, in: graph, tolerance: tolerance, limits: limits).occurrences
    }
    public func expand(_ assembly: DocumentAssembly, in graph: DesignGraph,
                       tolerance: ModelingTolerance,
                       limits: AssemblyResourceLimits = .standard) throws -> AssemblyExpansionResult {
        try limits.validate()
        var execution = try OriginalQueryExecution(
            budget: OriginalQueryBudget(workLimit: limits.maximumWork, sourceTextByteLimit: limits.maximumTextBytes, recordLimit: limits.maximumRecords,
                allocationPolicy: .bytes),
            limits: .init(maximumValueDepth: limits.maximumAlgebraicDepth,
                maximumCoefficientDepth: limits.maximumAlgebraicDepth,
                remainingSourceDepth: limits.maximumDepth))
        return try expand(assembly, in: graph, tolerance: tolerance, limits: limits, using: &execution)
    }

    public func expand(_ assembly: DocumentAssembly, in graph: DesignGraph,
        tolerance: ModelingTolerance, limits: AssemblyResourceLimits,
        using execution: inout OriginalQueryExecution) throws -> AssemblyExpansionResult {
        try limits.validate(); try tolerance.validate()
        let startingWork = execution.localWork
        let result = try execution.withAllocationScope(policy: .bytes,
            recordLimit: limits.maximumRecords, sourceTextByteLimit: limits.maximumTextBytes, workLimit: limits.maximumWork) { execution in
            try expandSource(assembly, in: graph, tolerance: tolerance, limits: limits, using: &execution)
        }
        return AssemblyExpansionResult(occurrences: result.occurrences,
            consumedWork: execution.localWork - startingWork)
    }

    private func expandSource(_ assembly: DocumentAssembly, in graph: DesignGraph,
        tolerance: ModelingTolerance, limits: AssemblyResourceLimits,
        using execution: inout OriginalQueryExecution) throws -> AssemblyExpansionResult {
        try limits.validate(); try tolerance.validate(); try execution.checkpoint()
        let startingWork = execution.localWork
        let startingRecords = execution.localRecords
        guard !assembly.roots.isEmpty else { throw AssemblyError.invalidSource("Assembly requires at least one root occurrence.") }
        var records: Int { execution.localRecords - startingRecords }
        for count in [assembly.roots.count, assembly.products.count, assembly.formations.count, assembly.definitions.count] {
            guard count <= limits.maximumRecords - records else { throw AssemblyError.resourceLimitExceeded("source records") }
            try execution.consumeRecords(count)
        }
        guard assembly.roots.count <= limits.maximumOccurrences else { throw AssemblyError.resourceLimitExceeded("source records") }
        guard records <= limits.maximumWork else { throw AssemblyError.resourceLimitExceeded("source work") }
        try execution.consumeWork(records)
        var sourceWork: Int { execution.localWork - startingWork }
        let startingTextBytes = execution.localSourceTextBytes
        var textBytes: Int { execution.localSourceTextBytes - startingTextBytes }
        func text(_ value: String?) throws {
            guard let value else { return }
            var count = 0
            let workRemaining = limits.maximumWork - sourceWork
            for _ in value.utf8 {
                guard count < limits.maximumTextBytes - textBytes, count < workRemaining else {
                    throw AssemblyError.resourceLimitExceeded("source text/work")
                }
                count += 1
                if count.isMultiple(of: 1024) { try execution.checkpoint() }
            }
            try execution.chargeSourceText(work: count, storageBytes: count)
        }
        var products = Set<AssemblyProductID>()
        for product in assembly.products {
            try CurrentTaskCancellationChecker().checkCancellation()
            try text(product.identifier); try text(product.name); try text(product.description)
            guard products.insert(product.id).inserted else { throw AssemblyError.invalidSource("Duplicate product identity.") }
        }
        var formations: [AssemblyProductFormationID: AssemblyProductFormation] = [:]
        var versions: [AssemblyProductID: Set<AssemblySourceText>] = [:]
        for formation in assembly.formations {
            try CurrentTaskCancellationChecker().checkCancellation()
            try text(formation.versionIdentifier); try text(formation.description)
            guard products.contains(formation.productID) else { throw AssemblyError.invalidSource("Missing product.") }
            guard formations.updateValue(formation, forKey: formation.id) == nil else {
                throw AssemblyError.invalidSource("Duplicate formation identity.")
            }
            guard versions[formation.productID, default: []].insert(AssemblySourceText(formation.versionIdentifier)).inserted else {
                throw AssemblyError.invalidSource("Formation version is not unique within its product.")
            }
        }
        var usedFormations = Set<AssemblyProductFormationID>()
        var definitions: [AssemblyDefinitionID: AssemblyDefinition] = [:]
        var edgeIDs = Set<AssemblyOccurrenceID>()
        for definition in assembly.definitions {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard definition.children.count <= limits.maximumRecords - records,
                  definition.features.count <= limits.maximumRecords - records - definition.children.count else {
                throw AssemblyError.resourceLimitExceeded("source records")
            }
            let additional = definition.children.count + definition.features.count
            try execution.consumeRecords(additional)
            guard additional <= limits.maximumWork - sourceWork else { throw AssemblyError.resourceLimitExceeded("source work") }
            try execution.consumeWork(additional)
            try text(definition.identifier); try text(definition.definitionDescription)
            guard formations[definition.formationID] != nil else { throw AssemblyError.invalidSource("Missing product formation.") }
            usedFormations.insert(definition.formationID)
            guard definitions.updateValue(definition, forKey: definition.id) == nil,
                  Set(definition.features).count == definition.features.count else {
                throw AssemblyError.invalidSource("Duplicate definition or local feature reference.")
            }
            for id in definition.features {
                guard let feature = graph.nodes[id], !feature.isSuppressed,
                      feature.bodyOrSheetOutput != nil else { throw AssemblyError.missingFeature(id) }
            }
        }
        guard usedFormations.count == formations.count,
              Set(formations.values.map { $0.productID }).count == products.count else {
            throw AssemblyError.invalidSource("Unreferenced product or formation.")
        }
        for occurrence in assembly.roots + assembly.definitions.flatMap({ $0.children }) {
            try CurrentTaskCancellationChecker().checkCancellation()
            try text(occurrence.name)
            guard edgeIDs.insert(occurrence.id).inserted else {
                throw AssemblyError.invalidSource("Duplicate direct occurrence identity.")
            }
            guard definitions[occurrence.definitionID] != nil else {
                throw AssemblyError.missingDefinition(occurrence.definitionID)
            }
            let directFactorCount: Int
            if case .word(let word) = occurrence.placement { directFactorCount = word.factors.count }
            else { directFactorCount = 1 }
            guard directFactorCount <= limits.maximumRecords - records,
                  directFactorCount <= (limits.maximumWork - sourceWork) / 14 else {
                throw AssemblyError.resourceLimitExceeded("original placement source records")
            }
            try execution.consumeRecords(directFactorCount); try execution.consumeWork(directFactorCount * 14)
            func stepSource(_ source: OriginalSTEPPlacementSource) throws {
                func element(_ value: OriginalSTEPPlacementElement?) throws {
                    guard let value else { return }
                    guard records < limits.maximumRecords, sourceWork < limits.maximumWork else {
                        throw AssemblyError.resourceLimitExceeded("original STEP placement records")
                    }
                    try execution.consumeRecords(1); try execution.consumeWork(1)
                    try text(value.name)
                }
                switch source {
                case .axis2(let value):
                    try element(value.location); try element(value.axis); try element(value.referenceDirection)
                case .cartesian(let value):
                    try element(value.location); try element(value.axis1); try element(value.axis2); try element(value.axis3)
                }
                guard source.adjustments.count <= limits.maximumRecords - records,
                      source.adjustments.count <= limits.maximumWork - sourceWork else {
                    throw AssemblyError.resourceLimitExceeded("original STEP adjustment records")
                }
                try execution.consumeRecords(source.adjustments.count); try execution.consumeWork(source.adjustments.count)
            }
            if case .step(let source) = occurrence.placement { try stepSource(source) }
            else if case .word(let word) = occurrence.placement {
                for factor in word.factors {
                    if case .step(let source) = factor.originalPlacement { try stepSource(source) }
                }
            }
            try occurrence.placement.validate(tolerance: tolerance,
                maximumAlgebraicDepth: limits.maximumAlgebraicDepth,
                maximumSourceDepth: limits.maximumDepth, using: &execution)
        }
        var result: [ExpandedAssemblyOccurrence] = []
        var reached = Set<AssemblyDefinitionID>()
        var work: Int { execution.localWork - startingWork }
        var stack = assembly.roots.sorted { $1.id < $0.id }.map {
            (occurrence: $0, path: [AssemblyOccurrenceID](), ancestors: Set<AssemblyDefinitionID>(),
             parent: [AssemblyPlacementFactor]())
        }
        while let item = stack.popLast() {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard !item.ancestors.contains(item.occurrence.definitionID) else {
                throw AssemblyError.cycle(item.occurrence.definitionID)
            }
            guard item.path.count < limits.maximumDepth, result.count < limits.maximumOccurrences,
                  item.path.count + 1 <= limits.maximumWork - min(work, limits.maximumWork) else {
                throw AssemblyError.resourceLimitExceeded("occurrence expansion")
            }
            try execution.consumeWork(item.path.count + 1)
            let path = item.path + [item.occurrence.id]
            // Retain the original source word instead of rounded composed columns.
            // Fourteen scalar/operation records per factor are admitted before its array copy.
            let directFactorCount: Int
            if case .word(let word) = item.occurrence.placement { directFactorCount = word.factors.count }
            else { directFactorCount = 1 }
            let factorCount = item.parent.count.addingReportingOverflow(directFactorCount)
            let retention = factorCount.partialValue.multipliedReportingOverflow(by: 14)
            guard !factorCount.overflow, !retention.overflow, retention.partialValue <= limits.maximumWork - work else {
                throw AssemblyError.resourceLimitExceeded("original placement word storage")
            }
            try execution.consumeWork(retention.partialValue)
            var factors = item.parent
            factors.reserveCapacity(factorCount.partialValue)
            if case .word(let word) = item.occurrence.placement { factors.append(contentsOf: word.factors) }
            else { factors.append(.forward(item.occurrence.placement)) }
            let frame = try AssemblyPlacementWord(factors: factors)
            result.append(ExpandedAssemblyOccurrence(path: AssemblyOccurrencePath(path),
                definitionID: item.occurrence.definitionID, placement: frame))
            reached.insert(item.occurrence.definitionID)
            guard let definition = definitions[item.occurrence.definitionID] else {
                throw AssemblyError.missingDefinition(item.occurrence.definitionID)
            }
            guard definition.children.count <= limits.maximumOccurrences - result.count - stack.count else {
                throw AssemblyError.resourceLimitExceeded("pending occurrences")
            }
            var ancestors = item.ancestors; ancestors.insert(definition.id)
            for child in definition.children.sorted(by: { $1.id < $0.id }) {
                stack.append((child, path, ancestors, factors))
            }
        }
        guard reached.count == definitions.count else {
            throw AssemblyError.invalidSource("Assembly contains an unreachable definition.")
        }
        return AssemblyExpansionResult(occurrences: result, consumedWork: execution.localWork - startingWork)
    }
}
