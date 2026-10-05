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
        let expansion = try DocumentAssemblyValidator().expand(assembly, in: graph,
            tolerance: tolerance, limits: limits)
        let expanded = expansion.occurrences
        let usage = try AssemblyEvaluationUsage(maximumWork: limits.maximumWork,
            consumedWork: expansion.consumedWork)
        let sourceDepth = min(16, limits.maximumDepth)
        let subdivisionDepth = min(32, limits.maximumDepth)
        func certificate(_ model: BRepModel) throws -> ValidatedBRepModel {
            try ValidatedBRepModel(model, tolerance: tolerance, validationLevel: .exact,
                maximumSubdivisionDepth: subdivisionDepth, remainingSourceDepth: sourceDepth,
                consumeWork: { try usage.consume() }, consumeStorage: { try usage.consume($0) })
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): This public assembly path consumes the
        // bounded original BRep receipt; its lower correspondence/seam/chart-lift
        // callbacks must be complete before all original affine families are admitted.
        _ = try certificate(local.model)
        try usage.consume(local.subshapes.entries.count)
        try usage.consume(local.lineage.count)
        try local.subshapes.validate(against: local.model, lineage: local.lineage)
        let definitions = Dictionary(uniqueKeysWithValues: assembly.definitions.map { ($0.id, $0) })
        var models: [FeatureID: ValidatedBRepModel] = [:]
        var geometryCosts: [FeatureID: Int] = [:]
        var accountedBodies = Set<BodyID>()
        func chargeWork(_ count: Int) throws { try usage.consume(count) }
        for featureID in Set(assembly.definitions.flatMap(\.features)).sorted() {
            try Task.checkCancellation()
            try chargeWork(local.subshapes.entries.count)
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
                guard records <= usage.remainingWork - extractionRecords else {
                    throw AssemblyError.resourceLimitExceeded("local extraction records")
                }
                extractionRecords += records
            }
            guard extractionRecords <= usage.remainingWork / 16 else {
                throw AssemblyError.resourceLimitExceeded("local extraction traversal/storage")
            }
            try chargeWork(extractionRecords * 16)
            let model = try BRepBodySubmodelExtractor().extract(bodyIDs: bodyIDs, from: local.model)
            let cost = try AssemblyGeometryCounter.count(model, maximum: usage.remainingWork, maximumDepth: limits.maximumDepth)
            try chargeWork(cost)
            geometryCosts[featureID] = cost
            models[featureID] = try certificate(model)
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
            var algebra = AssemblyOriginalAlgebraAdmission(usage: usage, maximumDepth: limits.maximumAlgebraicDepth)
            let originalWord = try occurrence.placement.originalOperationWord(tolerance: tolerance,
                maximumDepth: limits.maximumAlgebraicDepth, maximumSourceDepth: limits.maximumDepth, usage: &algebra)
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
                guard geometryCost <= (usage.remainingWork) / 16 else {
                    throw AssemblyError.resourceLimitExceeded("world geometry work/storage")
                }
                try chargeWork(geometryCost * 16)
                guard count <= (usage.remainingWork) / 16 else {
                    throw AssemblyError.resourceLimitExceeded("world topology work")
                }
                try chargeWork(count * 16)
                let seed = namespace(path: occurrence.path, definition: definition.id, feature: featureID)
                guard namespaces.insert(seed).inserted else { throw AssemblyError.identityCollision }
                let placedModel = try shapeOperator.transformed(validatedModel: sourceCertificate,
                    by: originalWord, maximumSubdivisionDepth: subdivisionDepth,
                    remainingSourceDepth: sourceDepth,
                    consumeWork: { depth in
                        guard depth >= 0, depth <= subdivisionDepth else {
                            throw AssemblyError.resourceLimitExceeded("original affine subdivision depth")
                        }
                        try usage.consume()
                    }, consumeStorage: { try usage.consume($0) })
                _ = try certificate(placedModel)
                let image = try ImportedBRepTopologyReidentifier().reidentify(placedModel, featureID: seed)
                worldModels.append(image.model)
                let correspondence = AssemblyFeatureCorrespondence(featureID: featureID, bodies: image.bodyIDs,
                    faces: image.faceIDs, edges: image.edgeIDs, vertices: image.vertexIDs)
                features.append(correspondence)
                try chargeWork(local.subshapes.entries.count)
                for (sourceID, reference) in local.subshapes.entries {
                    let target: TopologyReference?
                    switch reference {
                    case .body(let id): target = image.bodyIDs[id].map(TopologyReference.body)
                    case .face(let id): target = image.faceIDs[id].map(TopologyReference.face)
                    case .edge(let id): target = image.edgeIDs[id].map(TopologyReference.edge)
                    case .vertex(let id): target = image.vertexIDs[id].map(TopologyReference.vertex)
                    }
                    guard let target else { continue }
                    guard occurrence.path.components.count <= (usage.remainingWork) / 37 else {
                        throw AssemblyError.resourceLimitExceeded("occurrence role text")
                    }
                    try chargeWork(occurrence.path.components.count * 37)
                    try chargeWork(sourceID.role.utf8.count)
                    let output = SubshapeID(featureID: sourceID.featureID,
                        role: "assembly/" + occurrence.path.description + "/" + sourceID.role, ordinal: sourceID.ordinal)
                    guard outputs.updateValue(target, forKey: output) == nil else { throw AssemblyError.identityCollision }
                    lineage[output] = TopologyLineage(output: output, relation: .generated)
                }
            }
            occurrences.append(AssemblyOccurrenceCorrespondence(path: occurrence.path, definitionID: definition.id,
                placement: occurrence.placement, features: features))
        }
        let world = try BRepModelCombiner().combined(worldModels)
        _ = try certificate(world)
        let index = SubshapeIndex(outputs)
        try usage.consume(outputs.count)
        try usage.consume(lineage.count)
        try index.validate(against: world, lineage: lineage)
        return AssemblyEvaluationResult(model: world, subshapes: index, lineage: lineage,
            artifact: AssemblyEvaluationArtifact(local: local, occurrences: occurrences, limits: limits), consumedWork: usage.consumedWork)
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
