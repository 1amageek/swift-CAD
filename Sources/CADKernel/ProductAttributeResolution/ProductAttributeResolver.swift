import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

public struct ProductAttributeResolver: ProductAttributeResolving {
    private let productLookup: any AssemblyProductLookingUp
    private let references: any StableSubshapeResolving
    private let sourceValidator: any ProductAttributesValidating
    public init(references: any StableSubshapeResolving = StableSubshapeResolver(),
                sourceValidator: any ProductAttributesValidating = ProductAttributesValidator(),
                productLookup: any AssemblyProductLookingUp = AssemblyProductLookup()) {
        self.productLookup = productLookup; self.references = references; self.sourceValidator = sourceValidator
    }
    public func sourceReference(for subshapeID: SubshapeID, in evaluated: EvaluatedDocument) throws -> StableSubshapeReference {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try sourceReference(for: subshapeID, in: evaluated, using: &execution)
    }
    public func sourceReference(for subshapeID: SubshapeID, in evaluated: EvaluatedDocument,
        using execution: inout OriginalQueryExecution) throws -> StableSubshapeReference {
        try execution.consumeWork(1)
        let local = evaluated.assembly?.local
        let index = local?.subshapes ?? evaluated.subshapes
        let topology = try index.reference(for: subshapeID)
        return StableSubshapeReference(subshapeID: subshapeID, geometrySignature: try SubshapeGeometrySignatureBuilder(
            model: local?.model ?? evaluated.brep, tolerance: evaluated.configuration.tolerance).signature(for: topology, using: &execution))
    }
    public func resolve(_ evaluated: EvaluatedDocument, limits: ProductAttributeLimits = .standard) throws -> ResolvedProductAttributes {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try resolve(evaluated, limits: limits, using: &execution)
    }
    public func resolve(_ evaluated: EvaluatedDocument, limits: ProductAttributeLimits = .standard, using execution: inout OriginalQueryExecution) throws -> ResolvedProductAttributes {
        var budget = try ProductAttributeBudget(limits: limits, using: &execution)
        let invocation = budget
        return try invocation.withExecution(using: &execution) { execution in

        let document = evaluated.document, source = document.productAttributes
        guard source.itemCharacterizations.count <= limits.maximumRecords,
              source.itemCharacterizations.count <= limits.maximumTargets else {
            throw ProductAttributeError.resourceLimitExceeded("Item characterization source records/targets.")
        }
        // Source validation and receipt equality inspect this original payload before
        // any complete-target hash or current-geometry signature may be constructed.
        try budget.charge(work: source.itemCharacterizations.count, using: &execution)
        for record in source.itemCharacterizations {
            if let geometry = record.target.geometry {
                try admitStoredSignature(geometry.geometrySignature, budget: &budget, using: &execution)
            }
        }
        try sourceValidator.validate(source, in: document, budget: &budget, using: &execution)
        let tolerance = evaluated.configuration.tolerance
        let local = evaluated.assembly?.local
        let model = local?.model ?? evaluated.brep, index = local?.subshapes ?? evaluated.subshapes
        let lineage = local?.lineage ?? evaluated.lineage
        try budget.charge(work: index.entries.count, using: &execution)
        try budget.charge(work: lineage.count, using: &execution)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Source association still invokes the
        // ordinary document fingerprint/equality producers. Public product resolution
        // must retain their full traversal admission before claiming whole-query work.
        if let cache = evaluated.caches.brep {
            guard try cache.sourceFingerprint == document.sourceFingerprint(tolerance: tolerance),
                  cache.model == evaluated.brep else { throw ProductAttributeError.inconsistentArtifact("Source/B-rep cache association.") }
        } else {
            guard let receipt = evaluated.validatedSourceReceipt, receipt.document == document,
                  receipt.tolerance == tolerance, let exact = evaluated.validatedBRep,
                  exact.tolerance == tolerance, exact.validationLevel != .modeling, exact.model == evaluated.brep else {
                throw ProductAttributeError.inconsistentArtifact("Missing or stale producer source/exact B-rep association.")
            }
        }
        if let assembly = document.assembly {
            guard let artifact = evaluated.assembly else { throw ProductAttributeError.inconsistentArtifact("Missing assembly artifact.") }
            let remaining = limits.maximumWork - budget.consumedWork
            guard remaining > 0 else { throw ProductAttributeError.resourceLimitExceeded("Assembly consistency work.") }
            let result = try AssemblyEvaluator().evaluate(assembly, in: document.designGraph, local: artifact.local,
                tolerance: tolerance, limits: AssemblyResourceLimits(maximumRecords: limits.maximumRecords,
                    maximumOccurrences: limits.maximumTargets, maximumDepth: limits.maximumDepth,
                    maximumTopologyEntities: limits.maximumTargets, maximumWork: remaining, maximumTextBytes: limits.maximumTextBytes - budget.consumedTextBytes), using: &execution)
            guard result.model == evaluated.brep, result.subshapes == evaluated.subshapes,
                  result.artifact.occurrences == artifact.occurrences, result.lineage == evaluated.lineage else {
                throw ProductAttributeError.inconsistentArtifact("Source/local/world correspondence.")
            }
        } else if evaluated.assembly != nil { throw ProductAttributeError.inconsistentArtifact("Unexpected assembly artifact.") }
        var localGeometry: [ProductAttributeTarget: TopologyReference] = [:]
        func geometry(_ target: ProductAttributeTarget, budget: inout ProductAttributeBudget, using execution: inout OriginalQueryExecution) throws -> TopologyReference? {
            guard let reference = target.geometry else { return nil }
            if let existing = localGeometry[target] { return existing }
            // Admit the existing resolver's full index/lineage scan before its fallback allocations.
            try budget.charge(work: index.entries.count, using: &execution)
            try budget.charge(work: lineage.count, using: &execution)
            let topology = try references.topologyReference(for: reference, model: model, subshapes: index,
                lineage: lineage, tolerance: tolerance, maximumSubdivisionDepth: 32, remainingSourceDepth: 16, maximumAlgebraicDepth: 32, using: &execution)
            switch topology {
            case let .body(id): guard model.bodies[id] != nil else { throw ProductAttributeError.missingTarget("Local body.") }
            case let .face(id): guard model.faces[id] != nil else { throw ProductAttributeError.missingTarget("Local face.") }
            default: throw ProductAttributeError.invalidSource("Product geometry target must be body or face.")
            }
            try budget.charge(targets: 1, using: &execution)
            try execution.retainStorage(count: 1, stride: MemoryLayout<(ProductAttributeTarget, TopologyReference)>.stride)
            localGeometry[target] = topology
            return topology
        }
        for record in source.itemCharacterizations {
            guard let reference = record.target.geometry else {
                throw ProductAttributeError.invalidSource("Item characterization requires geometry.")
            }
            try budget.charge(work: index.entries.count, using: &execution)
            try budget.charge(work: lineage.count, using: &execution)
            if index[reference.subshapeID] == nil {
                // The provenance resolver may construct signatures for same-feature
                // candidates. Admit their actual payload before invoking that fallback.
                for entry in lineage.values { try budget.charge(work: entry.parents.count, using: &execution) }
                for (id, candidate) in index.entries where id.featureID == reference.subshapeID.featureID {
                    switch (record.target.kind, candidate) {
                    case (.body, .body), (.face, .face):
                        try admitActualSignature(candidate, model: model, budget: &budget, using: &execution)
                    default: break
                    }
                }
            }
            let topology = try references.topologyReference(for: reference, model: model,
                subshapes: index, lineage: lineage, tolerance: tolerance, maximumSubdivisionDepth: 32, remainingSourceDepth: 16, maximumAlgebraicDepth: 32, using: &execution)
            try admitActualSignature(topology, model: model, budget: &budget, using: &execution)
            let builder = SubshapeGeometrySignatureBuilder(model: model, tolerance: tolerance)
            let actual = try builder.signature(for: topology, using: &execution)
            // Match and cache consume the complete source signature independently of
            // the stable resolver's intentionally provenance-first direct-ID policy.
            try admitStoredSignature(reference.geometrySignature, budget: &budget, using: &execution)
            guard try builder.matches(reference.geometrySignature, actual, using: &execution) else {
                throw ProductAttributeError.inconsistentArtifact("Item characterization does not match current local geometry.")
            }
            try admitStoredSignature(reference.geometrySignature, budget: &budget, using: &execution)
            try budget.charge(targets: 1, using: &execution)
            try execution.retainStorage(count: 1, stride: MemoryLayout<(ProductAttributeTarget, TopologyReference)>.stride)
            localGeometry[record.target] = topology
        }
        func metadataGeometry(_ target: ProductAttributeTarget, budget: inout ProductAttributeBudget, using execution: inout OriginalQueryExecution) throws {
            try budget.charge(work: 1, using: &execution)
            if let reference = target.geometry { try admitStoredSignature(reference.geometrySignature, budget: &budget, using: &execution) }
            if let topology = try geometry(target, budget: &budget, using: &execution), let reference = target.geometry {
                try admitActualSignature(topology, model: model, budget: &budget, using: &execution)
                let builder = SubshapeGeometrySignatureBuilder(model: model, tolerance: tolerance)
                let actual = try builder.signature(for: topology, using: &execution)
                guard try builder.matches(reference.geometrySignature, actual, using: &execution) else {
                    throw ProductAttributeError.inconsistentArtifact("Product metadata target does not match current source geometry.")
                }
            }
        }
        for datum in source.manufacturingInformation.datums { try metadataGeometry(datum.target, budget: &budget, using: &execution) }
        for dimension in source.manufacturingInformation.dimensions {
            try metadataGeometry(dimension.target, budget: &budget, using: &execution)
            if let reference = dimension.referenceTarget { try metadataGeometry(reference, budget: &budget, using: &execution) }
        }
        for tolerance in source.manufacturingInformation.tolerances { try metadataGeometry(tolerance.target, budget: &budget, using: &execution) }
        for annotation in source.manufacturingInformation.annotations {
            for target in annotation.targets { try metadataGeometry(target, budget: &budget, using: &execution) }
        }
        for property in source.viewMetadata.validationProperties { try metadataGeometry(property.target, budget: &budget, using: &execution) }
        for record in source.shapeElementDescriptions { try metadataGeometry(record.target, budget: &budget, using: &execution) }
        for assignment in source.assignments { _ = try geometry(assignment.target, budget: &budget, using: &execution) }
        for layer in source.layers { for member in layer.members { _ = try geometry(member, budget: &budget, using: &execution) } }
        var candidates: [(ResolvedProductTarget, TopologyReference?, FeatureID?)] = []
        var candidateIDs = Set<ResolvedProductTarget>()
        func append(_ target: ResolvedProductTarget, local: TopologyReference?, feature: FeatureID?, budget: inout ProductAttributeBudget, using execution: inout OriginalQueryExecution) throws {
            try budget.charge(work: 1, targets: 1, using: &execution)
            try execution.retainStorage(count: 1, stride: MemoryLayout<ResolvedProductTarget>.stride)
            if candidateIDs.insert(target).inserted {
                try execution.retainStorage(count: 1, stride: MemoryLayout<(ResolvedProductTarget, TopologyReference?, FeatureID?)>.stride)
                candidates.append((target, local, feature))
            }
        }
        if let artifact = evaluated.assembly {
            for occurrence in artifact.occurrences {
                try append(ResolvedProductTarget(definitionID: occurrence.definitionID, path: occurrence.path), local: nil, feature: nil, budget: &budget, using: &execution)
                for feature in occurrence.features {
                    for (localID, worldID) in feature.bodies {
                        try append(ResolvedProductTarget(topology: .body(worldID), definitionID: occurrence.definitionID, path: occurrence.path),
                            local: .body(localID), feature: feature.featureID, budget: &budget, using: &execution)
                    }
                    for (localID, worldID) in feature.faces {
                        try append(ResolvedProductTarget(topology: .face(worldID), definitionID: occurrence.definitionID, path: occurrence.path),
                            local: .face(localID), feature: feature.featureID, budget: &budget, using: &execution)
                    }
                }
            }
            for definition in document.assembly?.definitions ?? [] {
                try append(ResolvedProductTarget(definitionID: definition.id), local: nil, feature: nil, budget: &budget, using: &execution)
            }
        } else {
            for (subshape, topology) in index.entries {
                switch topology {
                case .body, .face: try append(ResolvedProductTarget(topology: topology), local: topology, feature: subshape.featureID, budget: &budget, using: &execution)
                default: break
                }
            }
        }
        func contains(_ bodyID: BodyID, faceID: FaceID, budget: inout ProductAttributeBudget, using execution: inout OriginalQueryExecution) throws -> Bool {
            guard let body = model.bodies[bodyID] else { throw ProductAttributeError.missingTarget("Body membership.") }
            for shellID in try body.originalShellIDs(using: &execution) {
                guard let shell = model.shells[shellID] else { throw ProductAttributeError.missingTarget("Body shell membership.") }
                try budget.charge(work: shell.faceIDs.count + 1, using: &execution)
                if shell.faceIDs.contains(faceID) { return true }
            }
            return false
        }
        func applies(_ target: ProductAttributeTarget, candidate: (ResolvedProductTarget, TopologyReference?, FeatureID?),
                     property: ProductAttributeValue.Property?, budget: inout ProductAttributeBudget, using execution: inout OriginalQueryExecution) throws -> Bool {
            try budget.charge(work: 1, using: &execution)
            let (world, localTopology, featureID) = candidate
            if let path = target.path, path != world.path { return false }
            switch target.kind {
            case .part: return target.definitionID == world.definitionID
            case .occurrence: return target.path == world.path
            case .directUsage: return target.usageID == world.path?.components.last
            case .body, .face:
                if let definition = target.definitionID, definition != world.definitionID { return false }
                guard target.geometry?.subshapeID.featureID == featureID, let topology = localGeometry[target], let localTopology else { return false }
                if topology == localTopology { return true }
                if property == .name { return false }
                if case let .body(bodyID) = topology, case let .face(faceID) = localTopology {
                    return try contains(bodyID, faceID: faceID, budget: &budget, using: &execution)
                }
                return false
            }
        }
        var byID: [ProductAttributeID: ProductAttributeAssignment] = [:]
        try execution.retainStorage(count: source.assignments.count, stride: MemoryLayout<(ProductAttributeID, ProductAttributeAssignment)>.stride)
        byID.reserveCapacity(source.assignments.count)
        for assignment in source.assignments {
            try execution.consumeWork(1); byID[assignment.id] = assignment
        }
        var values: [ResolvedProductTarget: ResolvedProductProperties] = [:]
        for candidate in candidates {
            var grouped: [ProductAttributeValue.Property: [ProductAttributeAssignment]] = [:]
            for assignment in source.assignments where try applies(assignment.target, candidate: candidate, property: assignment.value.property, budget: &budget, using: &execution) {
                try budget.charge(work: 1, using: &execution)
                try execution.retainStorage(count: 1, stride: MemoryLayout<ProductAttributeAssignment>.stride)
                if grouped[assignment.value.property] == nil {
                    try execution.retainStorage(count: 1, stride: MemoryLayout<(ProductAttributeValue.Property, [ProductAttributeAssignment])>.stride)
                }
                grouped[assignment.value.property, default: []].append(assignment)
            }
            var properties: [ProductAttributeValue.Property: ResolvedProductProperty] = [:]
            for (property, applicable) in grouped {
                var overridden = Set<ProductAttributeID>()
                for assignment in applicable {
                    var cursor = assignment.overrides
                    while let id = cursor {
                        try budget.charge(work: 1, using: &execution)
                        try execution.retainStorage(count: 1, stride: MemoryLayout<ProductAttributeID>.stride)
                        overridden.insert(id); cursor = byID[id]?.overrides
                    }
                }
                try execution.retainStorage(count: applicable.count, stride: MemoryLayout<ProductAttributeAssignment>.stride)
                let winners = try applicable.filter { assignment in
                    try execution.consumeWork(1); return !overridden.contains(assignment.id)
                }
                guard winners.count == 1, let winner = winners.first else { throw ProductAttributeError.ambiguousProperty(property.rawValue) }
                var chain: [ProductAttributeID] = [], cursor: ProductAttributeAssignment? = winner
                while let assignment = cursor {
                    try budget.charge(work: 1, using: &execution)
                    guard try applies(assignment.target, candidate: candidate, property: property, budget: &budget, using: &execution) else {
                        throw ProductAttributeError.invalidSource("Override predecessor is not applicable to the selected target.")
                    }
                    try execution.retainStorage(count: 1, stride: MemoryLayout<ProductAttributeID>.stride)
                    chain.append(assignment.id); cursor = assignment.overrides.flatMap { byID[$0] }
                }
                var value = winner.value
                if case let .descriptorDensity(id) = value {
                    try budget.charge(work: source.materials.count, using: &execution)
                    guard let density = source.materials.first(where: { $0.id == id })?.density else {
                        throw ProductAttributeError.missingTarget("Assigned descriptor density value.")
                    }
                    value = .density(density)
                }
                try execution.retainStorage(count: chain.count, stride: MemoryLayout<ProductAttributeID>.stride)
                try execution.consumeWork(chain.count)
                try execution.retainStorage(count: 1, stride: MemoryLayout<(ProductAttributeValue.Property, ResolvedProductProperty)>.stride)
                properties[property] = ResolvedProductProperty(value: value, assignmentChain: Array(chain.reversed()))
            }
            var layers = Set<ProductLayerID>()
            for layer in source.layers {
                for member in layer.members where try applies(member, candidate: candidate, property: nil, budget: &budget, using: &execution) {
                    try execution.retainStorage(count: 1, stride: MemoryLayout<ProductLayerID>.stride)
                    layers.insert(layer.id)
                }
            }
            let target = candidate.0
            var name: String?
            if target.topology == nil, let id = target.definitionID {
                if let assembly = document.assembly {
                    let result = try productLookup.product(for: id, in: assembly,
                        maximumWork: limits.maximumWork - budget.consumedWork, using: &execution)
                    name = result.product.name
                }
                if let path = target.path {
                    var children = document.assembly?.roots ?? []
                    for component in path.components {
                        try budget.charge(work: children.count + (document.assembly?.definitions.count ?? 0), using: &execution)
                        guard let occurrence = children.first(where: { $0.id == component }) else { throw ProductAttributeError.missingTarget("Occurrence name.") }
                        name = occurrence.name
                        children = document.assembly?.definitions.first(where: { $0.id == occurrence.definitionID })?.children ?? []
                    }
                }
            }
            try execution.retainStorage(count: 1, stride: MemoryLayout<(ResolvedProductTarget, ResolvedProductProperties)>.stride)
            values[target] = ResolvedProductProperties(properties: properties, layers: layers, sourceName: name)
        }
        return ResolvedProductAttributes(documentID: document.id, values: values, localGeometry: localGeometry, consumedWork: budget.consumedWork)

        }
}

    private func admitStoredSignature(_ signature: SubshapeGeometrySignature,
                                      budget: inout ProductAttributeBudget, using execution: inout OriginalQueryExecution) throws {
        try budget.charge(work: 1, using: &execution)
        switch signature {
        case let .body(body):
            try budget.charge(work: 1, using: &execution)
            try budget.charge(work: body.shells.count, using: &execution)
            for shell in body.shells {
                try budget.charge(work: 1, using: &execution)
                try budget.charge(work: shell.faces.count, using: &execution)
                for face in shell.faces { try admitStoredFace(face, budget: &budget, using: &execution) }
            }
        case let .face(face): try admitStoredFace(face, budget: &budget, using: &execution)
        case let .edge(edge):
            try budget.charge(work: 8, using: &execution)
            try GeometryStructuralComparisonWork.charge(curve: edge.curve, using: &execution)
        case .vertex: try budget.charge(work: 3, using: &execution)
        }
    }

    private func admitStoredFace(_ face: FaceGeometrySignature,
                                 budget: inout ProductAttributeBudget, using execution: inout OriginalQueryExecution) throws {
        try budget.charge(work: 1, using: &execution)
        try budget.charge(work: face.loops.count, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: face.surface, using: &execution)
        for loop in face.loops {
            try budget.charge(work: 1, using: &execution)
            try budget.charge(work: loop.coedges.count, using: &execution)
            for coedge in loop.coedges {
                try budget.charge(work: 9, using: &execution)
                try GeometryStructuralComparisonWork.charge(curve: coedge.edge.curve, using: &execution)
                try GeometryStructuralComparisonWork.charge(parameterCurve: coedge.surfaceParameterCurve, using: &execution)
            }
        }
    }

    private func admitActualSignature(_ topology: TopologyReference, model: BRepModel,
                                      budget: inout ProductAttributeBudget, using execution: inout OriginalQueryExecution) throws {
        try budget.charge(work: 1, using: &execution)
        switch topology {
        case let .body(id):
            guard let body = model.bodies[id] else { throw ProductAttributeError.missingTarget("Item characterization local body.") }
            let shellIDs = try body.originalShellIDs(using: &execution)
            try budget.charge(work: shellIDs.count, targets: shellIDs.count, using: &execution)
            for shellID in shellIDs {
                try budget.charge(work: 2, using: &execution)
                guard let shell = model.shells[shellID] else { throw ProductAttributeError.missingTarget("Item characterization local shell.") }
                try budget.charge(work: shell.faceIDs.count, targets: shell.faceIDs.count, using: &execution)
                for faceID in shell.faceIDs { try admitActualFace(faceID, model: model, budget: &budget, using: &execution) }
            }
        case let .face(id): try admitActualFace(id, model: model, budget: &budget, using: &execution)
        default: throw ProductAttributeError.invalidSource("Item characterization must resolve to body or face geometry.")
        }
    }

    private func admitActualFace(_ id: FaceID, model: BRepModel,
                                 budget: inout ProductAttributeBudget, using execution: inout OriginalQueryExecution) throws {
        try budget.charge(work: 3, using: &execution)
        guard let face = model.faces[id], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw ProductAttributeError.missingTarget("Item characterization local face/surface.")
        }
        try budget.charge(work: face.loops.count, targets: face.loops.count, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
        for loopID in face.loops {
            try budget.charge(work: 2, using: &execution)
            guard let loop = model.loops[loopID] else { throw ProductAttributeError.missingTarget("Item characterization local loop.") }
            try budget.charge(work: loop.coedges.count, targets: loop.coedges.count, using: &execution)
            for coedge in loop.coedges {
                // Edge, both endpoint vertices, optional trim, and orientation are
                // fixed original records; coefficient arrays are owned by Geometry.
                try budget.charge(work: 12, using: &execution)
                guard let edge = model.edges[coedge.edgeID], let curve = model.geometry.curves[edge.curveID],
                      model.vertices[edge.startVertexID] != nil, model.vertices[edge.endVertexID] != nil else {
                    throw ProductAttributeError.missingTarget("Item characterization local edge/vertices.")
                }
                guard let parameterCurve = coedge.surfaceParameterCurve else {
                    throw ProductAttributeError.inconsistentArtifact("Item characterization local coedge has no p-curve.")
                }
                try GeometryStructuralComparisonWork.charge(curve: curve, using: &execution)
                try GeometryStructuralComparisonWork.charge(parameterCurve: parameterCurve, using: &execution)
            }
        }
    }
}
