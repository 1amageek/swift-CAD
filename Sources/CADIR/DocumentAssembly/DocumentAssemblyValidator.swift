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
        try limits.validate(); try tolerance.validate(); try Task.checkCancellation()
        guard !assembly.roots.isEmpty else { throw AssemblyError.invalidSource("Assembly requires at least one root occurrence.") }
        var records = assembly.roots.count
        guard records <= limits.maximumRecords, assembly.definitions.count <= limits.maximumRecords - records,
              assembly.roots.count <= limits.maximumOccurrences else { throw AssemblyError.resourceLimitExceeded("source records") }
        records += assembly.definitions.count
        guard records <= limits.maximumWork else { throw AssemblyError.resourceLimitExceeded("source work") }
        var definitions: [AssemblyDefinitionID: AssemblyDefinition] = [:]
        var edgeIDs = Set<AssemblyOccurrenceID>()
        for definition in assembly.definitions {
            try Task.checkCancellation()
            guard definition.children.count <= limits.maximumRecords - records,
                  definition.features.count <= limits.maximumRecords - records - definition.children.count else {
                throw AssemblyError.resourceLimitExceeded("source records")
            }
            records += definition.children.count + definition.features.count
            guard records <= limits.maximumWork else { throw AssemblyError.resourceLimitExceeded("source work") }
            guard definitions.updateValue(definition, forKey: definition.id) == nil,
                  Set(definition.features).count == definition.features.count else {
                throw AssemblyError.invalidSource("Duplicate definition or local feature reference.")
            }
            for id in definition.features {
                guard let feature = graph.nodes[id], !feature.isSuppressed,
                      feature.bodyOrSheetOutput != nil else { throw AssemblyError.missingFeature(id) }
            }
        }
        for occurrence in assembly.roots + assembly.definitions.flatMap(\.children) {
            try Task.checkCancellation()
            guard edgeIDs.insert(occurrence.id).inserted else {
                throw AssemblyError.invalidSource("Duplicate direct occurrence identity.")
            }
            guard definitions[occurrence.definitionID] != nil else {
                throw AssemblyError.missingDefinition(occurrence.definitionID)
            }
            try occurrence.placement.validate(tolerance: tolerance)
            guard !occurrence.placement.reversesOrientation else { throw AssemblyError.invalidPlacement }
        }
        var result: [ExpandedAssemblyOccurrence] = []
        var reached = Set<AssemblyDefinitionID>()
        var work = records
        var stack = assembly.roots.sorted { $1.id < $0.id }.map {
            (occurrence: $0, path: [AssemblyOccurrenceID](), ancestors: Set<AssemblyDefinitionID>(),
             parent: RigidTransform3D.translated(by: .zero))
        }
        while let item = stack.popLast() {
            try Task.checkCancellation()
            guard !item.ancestors.contains(item.occurrence.definitionID) else {
                throw AssemblyError.cycle(item.occurrence.definitionID)
            }
            guard item.path.count < limits.maximumDepth, result.count < limits.maximumOccurrences,
                  item.path.count + 1 <= limits.maximumWork - min(work, limits.maximumWork) else {
                throw AssemblyError.resourceLimitExceeded("occurrence expansion")
            }
            work += item.path.count + 1
            let path = item.path + [item.occurrence.id]
            let local = item.occurrence.placement
            let frame = try RigidTransform3D(basisX: item.parent.applying(to: local.basisX),
                basisY: item.parent.applying(to: local.basisY), basisZ: item.parent.applying(to: local.basisZ),
                translation: item.parent.applying(to: local.translation) + item.parent.translation, tolerance: tolerance)
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
                stack.append((child, path, ancestors, frame))
            }
        }
        guard reached.count == definitions.count else {
            throw AssemblyError.invalidSource("Assembly contains an unreachable definition.")
        }
        return AssemblyExpansionResult(occurrences: result, consumedWork: work)
    }
}
