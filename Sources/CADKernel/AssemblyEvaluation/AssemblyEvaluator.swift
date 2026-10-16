import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

public struct AssemblyEvaluator: AssemblyEvaluating {
    private let shapeOperator: any ShapeOperating
    public init(shapeOperator: any ShapeOperating = DefaultShapeOperator()) { self.shapeOperator = shapeOperator }
    public func evaluate(_ assembly: DocumentAssembly, in graph: DesignGraph,
                         local: AssemblyLocalEvaluationBase, tolerance: ModelingTolerance,
                         limits: AssemblyResourceLimits = .standard) throws -> AssemblyEvaluationResult {
        try limits.validate()
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(workLimit: limits.maximumWork,
            sourceTextByteLimit: limits.maximumTextBytes), limits: try .init(
                maximumValueDepth: limits.maximumAlgebraicDepth,
                maximumCoefficientDepth: limits.maximumAlgebraicDepth,
                remainingSourceDepth: limits.maximumDepth,
                maximumSubdivisionDepth: min(32, limits.maximumDepth)))
        return try evaluate(assembly, in: graph, local: local, tolerance: tolerance,
            limits: limits, using: &execution)
    }

    public func evaluate(_ assembly: DocumentAssembly, in graph: DesignGraph,
        local: AssemblyLocalEvaluationBase, tolerance: ModelingTolerance,
        limits: AssemblyResourceLimits = .standard, using execution: inout OriginalQueryExecution) throws -> AssemblyEvaluationResult {
        try limits.validate()
        let contribution = try execution.makeContributionHandle(workLimit: limits.maximumWork,
            sourceTextByteLimit: limits.maximumTextBytes,
            executionLimits: .init(maximumValueDepth: limits.maximumAlgebraicDepth,
                maximumCoefficientDepth: limits.maximumAlgebraicDepth,
                remainingSourceDepth: limits.maximumDepth,
                maximumSubdivisionDepth: min(32, limits.maximumDepth)))
        return try execution.withContributionScope(contribution) { execution in
            try evaluateBody(assembly, in: graph, local: local, tolerance: tolerance, limits: limits, using: &execution)
        }
    }

    private func evaluateBody(_ assembly: DocumentAssembly, in graph: DesignGraph,
        local: AssemblyLocalEvaluationBase, tolerance: ModelingTolerance,
        limits: AssemblyResourceLimits, using execution: inout OriginalQueryExecution) throws -> AssemblyEvaluationResult {
        let initialWork = execution.localWork
        let expansion = try DocumentAssemblyValidator().expand(assembly, in: graph,
            tolerance: tolerance, limits: limits, using: &execution)
        let expanded = expansion.occurrences
        let sourceDepth = min(16, limits.maximumDepth)
        let subdivisionDepth = min(32, limits.maximumDepth)
        func certificate(_ model: BRepModel, using execution: inout OriginalQueryExecution) throws -> ValidatedBRepModel {
            try ValidatedBRepModel(model, tolerance: tolerance, validationLevel: .exact,
                maximumSubdivisionDepth: subdivisionDepth, remainingSourceDepth: sourceDepth, using: &execution)
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): This public assembly path consumes the
        // bounded original BRep receipt; its lower correspondence/seam/chart-lift
        // callbacks must be complete before all original affine families are admitted.
        _ = try certificate(local.model, using: &execution)
        try execution.consumeWork(local.subshapes.entries.count)
        try execution.consumeWork(local.lineage.count)
        try local.subshapes.validate(against: local.model, lineage: local.lineage, using: &execution)
        let definitions = Dictionary(uniqueKeysWithValues: assembly.definitions.map { ($0.id, $0) })
        var models: [FeatureID: ValidatedBRepModel] = [:]
        var geometryCosts: [FeatureID: Int] = [:]
        var accountedBodies = Set<BodyID>()
        func chargeWork(_ count: Int, using execution: inout OriginalQueryExecution) throws { try execution.consumeWork(count) }
        for featureID in Set(assembly.definitions.flatMap(\.features)).sorted() {
            try Task.checkCancellation()
            try chargeWork(local.subshapes.entries.count, using: &execution)
            let bodyIDs = Set(local.subshapes.entries.compactMap { key, value -> BodyID? in
                guard key.featureID == featureID, case let .body(id) = value else { return nil }; return id
            })
            guard !bodyIDs.isEmpty else { throw AssemblyError.unresolvedOutput(featureID) }
            accountedBodies.formUnion(bodyIDs)
            // Extraction follows bounded ownership passes over the source topology.
            // Charge those passes before creating the extracted persistent-map copy.
            var extractionRecords = 0
            for records in [local.model.bodies.count, local.model.shells.count, local.model.faces.count,
                            local.model.loops.count, local.model.edges.count, local.model.vertices.count] {
                guard records <= execution.availableWork - extractionRecords else {
                    throw AssemblyError.resourceLimitExceeded("local extraction records")
                }
                extractionRecords += records
            }
            guard extractionRecords <= execution.availableWork / 16 else {
                throw AssemblyError.resourceLimitExceeded("local extraction traversal/storage")
            }
            try chargeWork(extractionRecords * 16, using: &execution)
            let model = try BRepBodySubmodelExtractor().extract(bodyIDs: bodyIDs, from: local.model, using: &execution)
            let cost = try AssemblyGeometryCounter.count(model, maximum: execution.availableWork, maximumDepth: limits.maximumDepth)
            try chargeWork(cost, using: &execution)
            geometryCosts[featureID] = cost
            models[featureID] = try certificate(model, using: &execution)
        }
        guard accountedBodies == Set(local.model.bodies.keys) else {
            throw AssemblyError.inconsistentArtifact("Assembly source does not account for every live local body.")
        }
        var worldModels: [BRepModel] = []
        var outputs: [SubshapeID: TopologyReference] = [:]
        var lineage = local.lineage
        var occurrences: [AssemblyOccurrenceCorrespondence] = []
        var topologyCount = 0
        var namespaces = Set<FeatureID>()
        for occurrence in expanded {
            try Task.checkCancellation()
            guard let definition = definitions[occurrence.definitionID] else {
                throw AssemblyError.missingDefinition(occurrence.definitionID)
            }
            let originalWord = try occurrence.placement.originalOperationWord(tolerance: tolerance,
                maximumDepth: limits.maximumAlgebraicDepth, maximumSourceDepth: limits.maximumDepth, using: &execution)
            var features: [AssemblyFeatureCorrespondence] = []
            for featureID in definition.features.sorted() {
                guard let sourceCertificate = models[featureID] else { throw AssemblyError.unresolvedOutput(featureID) }
                let source = sourceCertificate.model
                var count = 0
                for records in [source.bodies.count, source.shells.count, source.faces.count, source.loops.count,
                                source.edges.count, source.vertices.count, source.geometry.curves.count, source.geometry.surfaces.count] {
                    guard records <= limits.maximumTopologyEntities - topologyCount - count else {
                        throw AssemblyError.resourceLimitExceeded("world topology")
                    }
                    count += records
                }
                topologyCount += count
                // Extraction, exact transform, reidentification, merge, and correspondence traversals
                // have bounded passes; charge the complete owner operation before allocating a copy.
                guard let geometryCost = geometryCosts[featureID] else {
                    throw AssemblyError.inconsistentArtifact("Missing admitted local geometry cost.")
                }
                guard geometryCost <= (execution.availableWork) / 16 else {
                    throw AssemblyError.resourceLimitExceeded("world geometry work/storage")
                }
                try chargeWork(geometryCost * 16, using: &execution)
                guard count <= (execution.availableWork) / 16 else {
                    throw AssemblyError.resourceLimitExceeded("world topology work")
                }
                try chargeWork(count * 16, using: &execution)
                let seed = namespace(path: occurrence.path, definition: definition.id, feature: featureID)
                guard namespaces.insert(seed).inserted else { throw AssemblyError.identityCollision }
                let placedModel = try shapeOperator.transformed(validatedModel: sourceCertificate,
                    by: originalWord, maximumSubdivisionDepth: subdivisionDepth,
                    remainingSourceDepth: sourceDepth, using: &execution)
                _ = try certificate(placedModel, using: &execution)
                let image = try ImportedBRepTopologyReidentifier().reidentify(placedModel, featureID: seed, using: &execution)
                worldModels.append(image.model)
                let correspondence = AssemblyFeatureCorrespondence(featureID: featureID, bodies: image.bodyIDs,
                    faces: image.faceIDs, edges: image.edgeIDs, vertices: image.vertexIDs)
                features.append(correspondence)
                try chargeWork(local.subshapes.entries.count, using: &execution)
                for (sourceID, reference) in local.subshapes.entries {
                    let target: TopologyReference?
                    switch reference {
                    case .body(let id): target = image.bodyIDs[id].map(TopologyReference.body)
                    case .face(let id): target = image.faceIDs[id].map(TopologyReference.face)
                    case .edge(let id): target = image.edgeIDs[id].map(TopologyReference.edge)
                    case .vertex(let id): target = image.vertexIDs[id].map(TopologyReference.vertex)
                    }
                    guard let target else { continue }
                    guard occurrence.path.components.count <= (execution.availableWork) / 37 else {
                        throw AssemblyError.resourceLimitExceeded("occurrence role text")
                    }
                    try chargeWork(occurrence.path.components.count * 37, using: &execution)
                    try chargeWork(sourceID.role.utf8.count, using: &execution)
                    let output = SubshapeID(featureID: sourceID.featureID,
                        role: "assembly/" + occurrence.path.description + "/" + sourceID.role, ordinal: sourceID.ordinal)
                    guard outputs.updateValue(target, forKey: output) == nil else { throw AssemblyError.identityCollision }
                    lineage[output] = TopologyLineage(output: output, relation: .generated)
                }
            }
            occurrences.append(AssemblyOccurrenceCorrespondence(path: occurrence.path, definitionID: definition.id,
                placement: occurrence.placement, features: features))
        }
        let world = try BRepModelCombiner().combined(worldModels, using: &execution)
        _ = try certificate(world, using: &execution)
        let index = SubshapeIndex(outputs)
        try execution.consumeWork(outputs.count)
        try execution.consumeWork(lineage.count)
        try index.validate(against: world, lineage: lineage, using: &execution)
        return AssemblyEvaluationResult(model: world, subshapes: index, lineage: lineage,
            artifact: AssemblyEvaluationArtifact(local: local, occurrences: occurrences, limits: limits), consumedWork: execution.localWork - initialWork)
    }
    private func namespace(path: AssemblyOccurrencePath, definition: AssemblyDefinitionID, feature: FeatureID) -> FeatureID {
        // Fixed unsigned hashing is independent of Swift Hasher randomization and sibling order.
        // Any resulting namespace/topology collision is explicitly rejected before publication.
        var high: UInt64 = 0x415353454D424C59
        var low: UInt64 = 0xCBF29CE484222325
        for id in path.components { mix(id.bitPattern, high: &high, low: &low) }
        mix(definition.bitPattern, high: &high, low: &low)
        mix(feature.bitPattern, high: &high, low: &low)
        return FeatureID(highBits: high, lowBits: low)
    }
    private func mix(_ bits: (high: UInt64, low: UInt64), high: inout UInt64, low: inout UInt64) {
        high = (high ^ bits.high) &* 0x100000001B3
        high = (high ^ bits.low) &* 0x100000001B3
        low = (low ^ bits.low) &* 0x9E3779B97F4A7C15
        low = (low ^ bits.high) &* 0x9E3779B97F4A7C15
    }
}
