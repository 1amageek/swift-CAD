import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

// FIXME(INCOMPLETE_IMPLEMENTATION): DefaultFeatureEvaluator publishes the
// original plane/Bezier and finite two-B-spline tangent-chain construction through this port.
// Full F1 completion requires every mandatory nonplanar partner, terminal and
// interaction domain, with successful and failed public behavior.
struct KernelRollingBallFilletEvaluator: RollingBallFilletEvaluating {
    private let sewer: any BRepSewing
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving

    init(sewer: any BRepSewing, resolver: ParameterResolving,
         subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()) {
        self.sewer = sewer
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
    }

    func admits(feature: FeatureNode, context: EvaluationContext) throws -> Bool {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try admits(feature: feature, context: context, using: &execution)
    }

    func admits(feature: FeatureNode, context: EvaluationContext,
        using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.checkpoint()
        let result = try admitsBody(feature: feature, context: context, using: &execution)
        try execution.checkpoint()
        return result
    }

    private func admitsBody(feature: FeatureNode, context: EvaluationContext,
        using execution: inout OriginalQueryExecution) throws -> Bool {
        guard case .fillet(let fillet) = feature.operation,
              fillet.shape == .round, !fillet.allEdges, fillet.edges.count == 1,
              fillet.endRadius == nil, fillet.limits == nil, fillet.variablePoints.isEmpty,
              fillet.tangentEdges, !fillet.yBlend else { return false }
        try fillet.validate()
        try FeatureEvaluationBoundary.validateExactInput(
            context, featureID: feature.id, tolerance: context.tolerance, using: &execution)
        let selection = try selected(fillet, context: context, using: &execution)
        guard let body = context.brep.bodies[selection.bodyID], body.kind == .solid,
              body.shellIDs.count == 1, let shellID = body.shellIDs.first,
              let shell = context.brep.shells[shellID] else { return false }
        var partners: [(FaceID, Surface3D)] = []
        for faceID in shell.faceIDs {
            try execution.consumeWork(1)
            guard let face = context.brep.faces[faceID],
                  let surface = context.brep.geometry.surfaces[face.surfaceID] else {
                throw failure(.missingReference, feature, context, "Fillet source face is missing.")
            }
            var uses = 0
            for loopID in face.loops {
                guard let loop = context.brep.loops[loopID] else {
                    throw failure(.missingReference, feature, context, "Fillet source loop is missing.")
                }
                uses += loop.edges.filter { $0.edgeID == selection.edgeID }.count
            }
            guard uses <= 1 else { return false }
            if uses == 1 { partners.append((faceID, surface)) }
        }
        guard partners.count == 2 else { return false }
        let cap: FaceID
        switch (partners[0].1, partners[1].1) {
        case (.plane, .bSpline): cap = partners[0].0
        case (.bSpline, .plane): cap = partners[1].0
        case (.bSpline(let first), .bSpline(let second)):
            guard case .closed = first.uDomain, case .closed = first.vDomain,
                  case .closed = second.uDomain, case .closed = second.vDomain else { return false }
            cap = partners[0].0.description < partners[1].0.description
                ? partners[0].0 : partners[1].0
        default: return false
        }
        let chain = try RollingBallTangentChainResolver().resolve(
            selectedEdge: selection.edgeID, partner: cap, shell: shell,
            model: context.brep, tolerance: context.tolerance, using: &execution)
        try execution.checkpoint()
        return !chain.isEmpty
    }

    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try evaluate(feature: feature, context: context, using: &execution)
    }

    func evaluate(feature: FeatureNode, context: EvaluationContext,
        using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        try execution.checkpoint()
        try FeatureEvaluationBoundary.validateExactInput(
            context, featureID: feature.id, tolerance: context.tolerance, using: &execution)
        guard case .fillet(let fillet) = feature.operation else {
            throw failure(.invalidInput, feature, context, "Rolling-ball evaluation requires a fillet.")
        }
        try fillet.validate()
        let selection = try selected(fillet, context: context, using: &execution)
        let radius = try resolver.evaluate(fillet.radius, parameters: context.parameters, variables: [:])
        guard radius.kind == .length, radius.value.isFinite,
              radius.value > context.tolerance.distance else {
            throw failure(.invalidInput, feature, context, "Fillet radius must be a positive source length above tolerance.")
        }
        let input: ValidatedBRepModel
        if let retained = context.validatedBRep,
           retained.tolerance == context.tolerance, retained.validationLevel != .modeling,
           retained.model == context.brep {
            input = retained
        } else {
            input = try ValidatedBRepModel(context.brep, tolerance: context.tolerance,
                maximumSubdivisionDepth: 32, remainingSourceDepth: 16, using: &execution)
        }
        let request = try RollingBallFilletRequestBuilder(
            input: input, subshapes: context.subshapes.entries).build(
                featureID: feature.id, bodyID: selection.bodyID,
                edgeID: selection.edgeID, radius: radius.value, using: &execution)
        let sewn = try sewer.sew(request, tolerance: context.tolerance, using: &execution)
        let model = try BRepBodyModelReplacer().replacing(
            bodyID: selection.bodyID, with: sewn.bodyID, from: sewn.brep, in: context.brep, using: &execution)
        try model.validate(level: .volumetric, tolerance: context.tolerance,
            maximumSubdivisionDepth: 32, remainingSourceDepth: 16, using: &execution)
        let scope = try BodyTopologyScope(bodyID: selection.bodyID, model: context.brep, using: &execution)
        let removed = try scope.subshapeIDs(in: context.subshapes, using: &execution)
        try execution.checkpoint()
        return EvaluationResult(brep: model, subshapes: sewn.subshapes,
            removedSubshapeIDs: removed, lineage: sewn.lineage)
    }

    private func selected(_ fillet: FilletFeature, context: EvaluationContext,
        using execution: inout OriginalQueryExecution)
        throws -> (bodyID: BodyID, edgeID: EdgeID) {
        let bodyID = try context.bodyID(generatedBy: fillet.target.featureID)
        guard fillet.edges.count == 1, let reference = fillet.edges.first,
              case .edge(let edgeID) = try subshapeResolver.topologyReference(
                for: reference, model: context.brep, subshapes: context.subshapes,
                lineage: context.lineage, tolerance: context.tolerance,
                maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
                remainingSourceDepth: min(16, execution.effectiveLimits.remainingSourceDepth),
                maximumAlgebraicDepth: nil, using: &execution) else {
            throw KernelError(phase: .topology, code: .missingReference,
                tolerance: context.tolerance, message: "Rolling-ball fillet requires one current edge.")
        }
        let scope = try BodyTopologyScope(bodyID: bodyID, model: context.brep, using: &execution)
        guard scope.references.contains(.edge(edgeID)) else {
            throw KernelError(phase: .topology, code: .missingReference,
                tolerance: context.tolerance, message: "Selected fillet edge belongs to a different body.")
        }
        return (bodyID, edgeID)
    }

    private func failure(_ code: KernelErrorCode, _ feature: FeatureNode,
                         _ context: EvaluationContext, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: feature.id,
            tolerance: context.tolerance, message: message)
    }
}
