import CADCore
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
        let local = evaluated.assembly?.local
        let index = local?.subshapes ?? evaluated.subshapes
        let topology = try index.reference(for: subshapeID)
        return StableSubshapeReference(subshapeID: subshapeID, geometrySignature: try SubshapeGeometrySignatureBuilder(
            model: local?.model ?? evaluated.brep, tolerance: evaluated.configuration.tolerance).signature(for: topology))
    }
    public func resolve(_ evaluated: EvaluatedDocument, limits: ProductAttributeLimits = .standard) throws -> ResolvedProductAttributes {
        var budget = try ProductAttributeBudget(limits: limits)
        let document = evaluated.document, source = document.productAttributes
        try sourceValidator.validate(source, in: document, budget: &budget)
        let tolerance = evaluated.configuration.tolerance
        let local = evaluated.assembly?.local
        let model = local?.model ?? evaluated.brep, index = local?.subshapes ?? evaluated.subshapes
        let lineage = local?.lineage ?? evaluated.lineage
        try budget.charge(work: index.entries.count)
        try budget.charge(work: lineage.count)
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
                    maximumTopologyEntities: limits.maximumTargets, maximumWork: remaining, maximumTextBytes: limits.maximumTextBytes - budget.consumedTextBytes))
            try budget.charge(work: result.consumedWork)
            guard result.model == evaluated.brep, result.subshapes == evaluated.subshapes,
                  result.artifact.occurrences == artifact.occurrences, result.lineage == evaluated.lineage else {
                throw ProductAttributeError.inconsistentArtifact("Source/local/world correspondence.")
            }
        } else if evaluated.assembly != nil { throw ProductAttributeError.inconsistentArtifact("Unexpected assembly artifact.") }
        var localGeometry: [ProductAttributeTarget: TopologyReference] = [:]
        func geometry(_ target: ProductAttributeTarget, budget: inout ProductAttributeBudget) throws -> TopologyReference? {
            guard let reference = target.geometry else { return nil }
            if let existing = localGeometry[target] { return existing }
            // Admit the existing resolver's full index/lineage scan before its fallback allocations.
            try budget.charge(work: index.entries.count)
            try budget.charge(work: lineage.count)
            let topology = try references.topologyReference(for: reference, model: model, subshapes: index,
                lineage: lineage, tolerance: tolerance)
            switch topology {
            case let .body(id): guard model.bodies[id] != nil else { throw ProductAttributeError.missingTarget("Local body.") }
            case let .face(id): guard model.faces[id] != nil else { throw ProductAttributeError.missingTarget("Local face.") }
            default: throw ProductAttributeError.invalidSource("Product geometry target must be body or face.")
            }
            try budget.charge(targets: 1)
            localGeometry[target] = topology
            return topology
        }
        for assignment in source.assignments { _ = try geometry(assignment.target, budget: &budget) }
        for layer in source.layers { for member in layer.members { _ = try geometry(member, budget: &budget) } }
        var candidates: [(ResolvedProductTarget, TopologyReference?, FeatureID?)] = []
        var candidateIDs = Set<ResolvedProductTarget>()
        func append(_ target: ResolvedProductTarget, local: TopologyReference?, feature: FeatureID?, budget: inout ProductAttributeBudget) throws {
            try budget.charge(work: 1, targets: 1)
            if candidateIDs.insert(target).inserted { candidates.append((target, local, feature)) }
        }
        if let artifact = evaluated.assembly {
            for occurrence in artifact.occurrences {
                try append(ResolvedProductTarget(definitionID: occurrence.definitionID, path: occurrence.path), local: nil, feature: nil, budget: &budget)
                for feature in occurrence.features {
                    for (localID, worldID) in feature.bodies {
                        try append(ResolvedProductTarget(topology: .body(worldID), definitionID: occurrence.definitionID, path: occurrence.path),
                            local: .body(localID), feature: feature.featureID, budget: &budget)
                    }
                    for (localID, worldID) in feature.faces {
                        try append(ResolvedProductTarget(topology: .face(worldID), definitionID: occurrence.definitionID, path: occurrence.path),
                            local: .face(localID), feature: feature.featureID, budget: &budget)
                    }
                }
            }
            for definition in document.assembly?.definitions ?? [] {
                try append(ResolvedProductTarget(definitionID: definition.id), local: nil, feature: nil, budget: &budget)
            }
        } else {
            for (subshape, topology) in index.entries {
                switch topology {
                case .body, .face: try append(ResolvedProductTarget(topology: topology), local: topology, feature: subshape.featureID, budget: &budget)
                default: break
                }
            }
        }
        func contains(_ bodyID: BodyID, faceID: FaceID, budget: inout ProductAttributeBudget) throws -> Bool {
            guard let body = model.bodies[bodyID] else { throw ProductAttributeError.missingTarget("Body membership.") }
            for shellID in body.shellIDs {
                guard let shell = model.shells[shellID] else { throw ProductAttributeError.missingTarget("Body shell membership.") }
                try budget.charge(work: shell.faceIDs.count + 1)
                if shell.faceIDs.contains(faceID) { return true }
            }
            return false
        }
        func applies(_ target: ProductAttributeTarget, candidate: (ResolvedProductTarget, TopologyReference?, FeatureID?),
                     property: ProductAttributeValue.Property?, budget: inout ProductAttributeBudget) throws -> Bool {
            try budget.charge(work: 1)
            let (world, localTopology, featureID) = candidate
            if let path = target.path, path != world.path { return false }
            switch target.kind {
            case .part: return target.definitionID == world.definitionID
            case .occurrence: return target.path == world.path
            case .directUsage: return target.usageID == world.path?.components.last
            case .body, .face:
                guard target.geometry?.subshapeID.featureID == featureID, let topology = localGeometry[target], let localTopology else { return false }
                if topology == localTopology { return true }
                if property == .name { return false }
                if case let .body(bodyID) = topology, case let .face(faceID) = localTopology {
                    return try contains(bodyID, faceID: faceID, budget: &budget)
                }
                return false
            }
        }
        var byID: [ProductAttributeID: ProductAttributeAssignment] = [:]
        for assignment in source.assignments { byID[assignment.id] = assignment }
        var values: [ResolvedProductTarget: ResolvedProductProperties] = [:]
        for candidate in candidates {
            var grouped: [ProductAttributeValue.Property: [ProductAttributeAssignment]] = [:]
            for assignment in source.assignments where try applies(assignment.target, candidate: candidate, property: assignment.value.property, budget: &budget) {
                try budget.charge(work: 1)
                grouped[assignment.value.property, default: []].append(assignment)
            }
            var properties: [ProductAttributeValue.Property: ResolvedProductProperty] = [:]
            for (property, applicable) in grouped {
                var overridden = Set<ProductAttributeID>()
                for assignment in applicable {
                    var cursor = assignment.overrides
                    while let id = cursor {
                        try budget.charge(work: 1)
                        overridden.insert(id); cursor = byID[id]?.overrides
                    }
                }
                let winners = applicable.filter { !overridden.contains($0.id) }
                guard winners.count == 1, let winner = winners.first else { throw ProductAttributeError.ambiguousProperty(property.rawValue) }
                var chain: [ProductAttributeID] = [], cursor: ProductAttributeAssignment? = winner
                while let assignment = cursor {
                    try budget.charge(work: 1)
                    guard try applies(assignment.target, candidate: candidate, property: property, budget: &budget) else {
                        throw ProductAttributeError.invalidSource("Override predecessor is not applicable to the selected target.")
                    }
                    chain.append(assignment.id); cursor = assignment.overrides.flatMap { byID[$0] }
                }
                var value = winner.value
                if case let .descriptorDensity(id) = value {
                    try budget.charge(work: source.materials.count)
                    guard let density = source.materials.first(where: { $0.id == id })?.density else {
                        throw ProductAttributeError.missingTarget("Assigned descriptor density value.")
                    }
                    value = .density(density)
                }
                properties[property] = ResolvedProductProperty(value: value, assignmentChain: Array(chain.reversed()))
            }
            var layers = Set<ProductLayerID>()
            for layer in source.layers {
                for member in layer.members where try applies(member, candidate: candidate, property: nil, budget: &budget) {
                    layers.insert(layer.id)
                }
            }
            let target = candidate.0
            var name: String?
            if target.topology == nil, let id = target.definitionID {
                if let assembly = document.assembly {
                    let result = try productLookup.product(for: id, in: assembly,
                        maximumWork: limits.maximumWork - budget.consumedWork)
                    try budget.charge(work: result.consumedWork)
                    name = result.product.name
                }
                if let path = target.path {
                    var children = document.assembly?.roots ?? []
                    for component in path.components {
                        try budget.charge(work: children.count + (document.assembly?.definitions.count ?? 0))
                        guard let occurrence = children.first(where: { $0.id == component }) else { throw ProductAttributeError.missingTarget("Occurrence name.") }
                        name = occurrence.name
                        children = document.assembly?.definitions.first(where: { $0.id == occurrence.definitionID })?.children ?? []
                    }
                }
            }
            values[target] = ResolvedProductProperties(properties: properties, layers: layers, sourceName: name)
        }
        return ResolvedProductAttributes(documentID: document.id, values: values, localGeometry: localGeometry, consumedWork: budget.consumedWork)
    }
}
