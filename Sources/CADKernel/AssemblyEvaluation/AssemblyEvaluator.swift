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
        try local.model.validate(level: .exact, tolerance: tolerance)
        try local.subshapes.validate(against: local.model, lineage: local.lineage)
        let definitions = Dictionary(uniqueKeysWithValues: assembly.definitions.map { ($0.id, $0) })
        var models: [FeatureID: BRepModel] = [:]
        var geometryCosts: [FeatureID: Int] = [:]
        var accountedBodies = Set<BodyID>()
        var work = expansion.consumedWork
        func chargeWork(_ count: Int) throws {
            guard count >= 0, count <= limits.maximumWork - work else {
                throw AssemblyError.resourceLimitExceeded("topology work")
            }
            work += count
        }
        for featureID in Set(assembly.definitions.flatMap(\.features)).sorted() {
            try Task.checkCancellation()
            try chargeWork(local.subshapes.entries.count)
            let bodyIDs = Set(local.subshapes.entries.compactMap { key, value -> BodyID? in
                guard key.featureID == featureID, case let .body(id) = value else { return nil }; return id
            })
            guard !bodyIDs.isEmpty else { throw AssemblyError.unresolvedOutput(featureID) }
            accountedBodies.formUnion(bodyIDs)
            let model = try BRepBodySubmodelExtractor().extract(bodyIDs: bodyIDs, from: local.model)
            let cost = try AssemblyGeometryCounter.count(model, maximum: limits.maximumWork - work, maximumDepth: limits.maximumDepth)
            try chargeWork(cost)
            geometryCosts[featureID] = cost
            models[featureID] = model
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
            var features: [AssemblyFeatureCorrespondence] = []
            for featureID in definition.features.sorted() {
                guard let source = models[featureID] else { throw AssemblyError.unresolvedOutput(featureID) }
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
                guard geometryCost <= (limits.maximumWork - work) / 16 else {
                    throw AssemblyError.resourceLimitExceeded("world geometry work/storage")
                }
                try chargeWork(geometryCost * 16)
                guard count <= (limits.maximumWork - work) / 16 else {
                    throw AssemblyError.resourceLimitExceeded("world topology work")
                }
                try chargeWork(count * 16)
                let seed = namespace(path: occurrence.path, definition: definition.id, feature: featureID)
                guard namespaces.insert(seed).inserted else { throw AssemblyError.identityCollision }
                var roots: [ShapeReference] = []
                for body in source.bodies.values.sorted(by: { $0.id < $1.id }) {
                    if body.kind == .solid { roots.append(.solid(body.id)) }
                    else { roots.append(contentsOf: body.shellIDs.map(ShapeReference.shell)) }
                }
                let transformed = try shapeOperator.transformed(Shape(root: .compound(roots), model: source),
                    by: occurrence.placement, tolerance: tolerance)
                var placedModel = transformed.model
                // Generic shell shapes own no body record. Retain the exact original sheet
                // ownership after transforming its shells, rather than treating it as a solid.
                for body in source.bodies.values where body.kind == .sheet { placedModel.bodies[body.id] = body }
                try placedModel.validate(level: .exact, tolerance: tolerance)
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
                    guard occurrence.path.components.count <= (limits.maximumWork - work) / 37 else {
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
        try world.validate(level: .exact, tolerance: tolerance)
        let index = SubshapeIndex(outputs)
        try index.validate(against: world, lineage: lineage)
        return AssemblyEvaluationResult(model: world, subshapes: index, lineage: lineage,
            artifact: AssemblyEvaluationArtifact(local: local, occurrences: occurrences, limits: limits), consumedWork: work)
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
