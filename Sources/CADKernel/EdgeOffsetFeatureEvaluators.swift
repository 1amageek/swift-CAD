import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// What Offset Edge and Offset Face Loop share: resolving their references and distance, and
/// imprinting the offsets (`BRepEdgeChainOffsetter`) with every open chain end carried on to its
/// face's boundary (`BRepImprintCompletion`, `.edge`).
struct EdgeOffsetImprint {
    let subshapeResolver: any StableSubshapeResolving
    let parameterResolver: any ParameterResolving

    func distance(_ expression: CADExpression, operation: String, context: EvaluationContext) throws -> Double {
        let quantity = try parameterResolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(operation: operation, expected: .length, actual: quantity.kind)
        }
        guard abs(quantity.value) > context.tolerance.distance, quantity.value.isFinite else {
            throw FeatureEvaluationError.invalidDistance(quantity.value)
        }
        return quantity.value
    }

    func faceID(_ reference: StableSubshapeReference, context: EvaluationContext) throws -> FaceID {
        guard case let .face(faceID) = try subshapeResolver.topologyReference(
            for: reference, model: context.brep, subshapes: context.subshapes, lineage: context.lineage, tolerance: context.tolerance
        ) else {
            throw FeatureEvaluationError.missingInput("An offset face could not be resolved.")
        }
        return faceID
    }

    func edgeID(_ reference: StableSubshapeReference, context: EvaluationContext) throws -> EdgeID {
        guard case let .edge(edgeID) = try subshapeResolver.topologyReference(
            for: reference, model: context.brep, subshapes: context.subshapes, lineage: context.lineage, tolerance: context.tolerance
        ) else {
            throw FeatureEvaluationError.missingInput("An offset edge could not be resolved.")
        }
        return edgeID
    }

    /// The faces of the body using `edgeID`.
    func faces(using edgeID: EdgeID, in bodyID: BodyID, model: BRepModel) -> [FaceID] {
        guard let body = model.bodies[bodyID] else { return [] }
        return body.shellIDs.flatMap { model.shells[$0]?.faceIDs ?? [] }.filter { faceID in
            model.faces[faceID]?.loops.contains { model.loops[$0]?.coedges.contains { $0.edgeID == edgeID } == true } == true
        }
    }

    /// The edges of a face's outer loop.
    func outerLoopEdges(of faceID: FaceID, model: BRepModel, tolerance: ModelingTolerance) throws -> [EdgeID] {
        guard let face = model.faces[faceID], let outer = face.loops.first, let loop = model.loops[outer] else {
            throw KernelError(phase: .topology, code: .missingReference, tolerance: tolerance, message: "An offset face has no outer loop.")
        }
        return loop.coedges.map(\.edgeID)
    }

    func imprint(
        _ groups: [(faceID: FaceID, edges: Set<EdgeID>)], distance: Double, gapFill: OffsetGapFill,
        on bodyID: BodyID, featureID: FeatureID, context: EvaluationContext
    ) throws -> EvaluationResult {
        var curves: [BRepFaceImprinter.Curve] = []
        for (index, group) in groups.enumerated() where group.edges.isEmpty == false {
            curves += try BRepEdgeChainOffsetter().offset(
                edges: group.edges, on: group.faceID, distance: distance, gapFill: gapFill, stableID: "offset:\(index)",
                model: context.brep, sourceSubshapes: context.subshapes.entries, tolerance: context.tolerance
            )
        }
        guard curves.isEmpty == false else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: context.tolerance,
                message: "There is nothing to offset.")
        }
        let completed = try BRepImprintCompletion().completed(
            curves, by: .edge, model: context.brep, sourceSubshapes: context.subshapes.entries, tolerance: context.tolerance
        )
        return try BRepFaceImprinter().imprint(completed, on: bodyID, featureID: featureID, context: context)
    }
}

/// Offset Edge (`EdgeOffsetFeature`): each chosen edge offset over the one support face it
/// bounds, and with symmetry also over the face on its other side.
struct EdgeOffsetFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let shared: EdgeOffsetImprint

    init(subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver(), parameterResolver: any ParameterResolving = ParameterResolver()) {
        shared = EdgeOffsetImprint(subshapeResolver: subshapeResolver, parameterResolver: parameterResolver)
    }

    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            guard case let .edgeOffset(offset) = feature.operation else {
                throw FeatureEvaluationError.invalidGraph("Edge offset evaluator requires an edgeOffset feature.")
            }
            try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) { try offset.validate() }
            try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
            let bodyID = try context.bodyID(generatedBy: offset.target.featureID)
            let distance = try shared.distance(offset.distance, operation: "edgeOffset.distance", context: context)
            guard distance > 0 else {
                throw FeatureEvaluationError.invalidDistance(distance)
            }
            let supports = try offset.supportFaces.map { try shared.faceID($0, context: context) }
            let edges = try offset.edges.map { try shared.edgeID($0, context: context) }
            var over: [FaceID: Set<EdgeID>] = [:]
            var across: [FaceID: Set<EdgeID>] = [:]
            for edge in edges {
                let faces = shared.faces(using: edge, in: bodyID, model: context.brep)
                let bounded = supports.filter(faces.contains)
                guard bounded.count == 1, let support = bounded.first else {
                    throw KernelError(phase: .evaluation, code: .invalidInput, featureID: feature.id, tolerance: context.tolerance,
                        message: bounded.isEmpty ? "An offset edge does not bound a support face." : "An offset edge bounds two support faces.")
                }
                over[support, default: []].insert(edge)
                if offset.isSymmetric {
                    for other in faces where other != support { across[other, default: []].insert(edge) }
                }
            }
            var groups: [(faceID: FaceID, edges: Set<EdgeID>)] = supports.map { ($0, over[$0] ?? []) }
            groups += across.keys.sorted().map { ($0, across[$0] ?? []) }
            return try shared.imprint(groups, distance: distance, gapFill: offset.gapFill, on: bodyID, featureID: feature.id, context: context)
        }
    }
}

/// Offset Face Loop (`FaceLoopOffsetFeature`): the chosen faces' outlines offset into the faces,
/// over the faces around them, or both; combined, only the outline of the chosen faces together
/// is offset.
struct FaceLoopOffsetFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let shared: EdgeOffsetImprint

    init(subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver(), parameterResolver: any ParameterResolving = ParameterResolver()) {
        shared = EdgeOffsetImprint(subshapeResolver: subshapeResolver, parameterResolver: parameterResolver)
    }

    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            guard case let .faceLoopOffset(offset) = feature.operation else {
                throw FeatureEvaluationError.invalidGraph("Face loop offset evaluator requires a faceLoopOffset feature.")
            }
            try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) { try offset.validate() }
            try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
            let bodyID = try context.bodyID(generatedBy: offset.target.featureID)
            let distance = try shared.distance(offset.distance, operation: "faceLoopOffset.distance", context: context)
            let faces = try offset.faces.map { try shared.faceID($0, context: context) }
            let chosen = Set(faces)
            var inward: [(faceID: FaceID, edges: Set<EdgeID>)] = []
            var outward: [FaceID: Set<EdgeID>] = [:]
            for face in faces {
                let outline = try shared.outerLoopEdges(of: face, model: context.brep, tolerance: context.tolerance)
                // Combined, an edge between two chosen faces is inside the outline, not on it.
                let edges = offset.isIndividual ? outline : outline.filter { edge in
                    shared.faces(using: edge, in: bodyID, model: context.brep).allSatisfy { $0 == face || chosen.contains($0) == false }
                }
                inward.append((face, Set(edges)))
                for edge in edges {
                    for other in shared.faces(using: edge, in: bodyID, model: context.brep) where other != face && (offset.isIndividual || chosen.contains(other) == false) {
                        outward[other, default: []].insert(edge)
                    }
                }
            }
            guard distance > 0 else {
                throw FeatureEvaluationError.invalidDistance(distance)
            }
            let outwardGroups = outward.keys.sorted().map { (faceID: $0, edges: outward[$0] ?? []) }
            let groups: [(faceID: FaceID, edges: Set<EdgeID>)] = switch offset.side {
            case .inward: inward
            case .outward: outwardGroups
            case .symmetric: inward + outwardGroups
            }
            return try shared.imprint(groups, distance: distance, gapFill: offset.gapFill, on: bodyID, featureID: feature.id, context: context)
        }
    }
}
