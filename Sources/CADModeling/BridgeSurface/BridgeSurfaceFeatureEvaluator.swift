import HashTreeCollections
import CADCore
import CADGeometry
import CADIR
import CADTopology

// FIXME(INCOMPLETE_IMPLEMENTATION): Constrained Bridge publishes only after
// whole-boundary continuity and sheet admission. The production CADKernel Bridge
// path still requires finite wall clipping and general wall-chart transfer before
// the full Bridge Surface contract may be reported complete.
public struct BridgeSurfaceFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let surfaceEvaluator: BSplineSurfaceFeatureEvaluator
    private let surfaceBuilder: any RuledBSplineSurfaceBuilding
    private let wallTrimmer: (any BridgeSurfaceWallTrimming)?
    private let sourceBudget: OriginalQueryBudget?
    private let sourceLimits: OriginalQueryExecutionLimits?
    private let subshapeResolver = StableSubshapeResolver()
    private let boundaryLoopResolver = OpenBoundaryLoopResolver()
    private let boundaryCurveResolver = ExactBoundaryCurveResolver()

    public init(
        surfaceEvaluator: BSplineSurfaceFeatureEvaluator = BSplineSurfaceFeatureEvaluator(),
        surfaceBuilder: any RuledBSplineSurfaceBuilding = ExactRuledBSplineSurfaceBuilder(),
        wallTrimmer: (any BridgeSurfaceWallTrimming)? = nil,
        sourceBudget: OriginalQueryBudget? = nil,
        sourceLimits: OriginalQueryExecutionLimits? = nil
    ) {
        self.surfaceEvaluator = surfaceEvaluator
        self.surfaceBuilder = surfaceBuilder
        self.wallTrimmer = wallTrimmer
        self.sourceBudget = sourceBudget; self.sourceLimits = sourceLimits
    }

    public func evaluate(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        guard (sourceBudget == nil) == (sourceLimits == nil) else {
            throw GeometryConversionError.invalidInput("Bridge source budget and limits must be supplied together.")
        }
        let budget = try sourceBudget ?? OriginalQueryBudget()
        let limits = try sourceLimits ?? OriginalQueryExecutionLimits(maximumValueDepth: 32,
            maximumCoefficientDepth: 32, remainingSourceDepth: 16,
            maximumSubdivisionDepth: 20, maximumSpans: 4096)
        var execution = OriginalQueryExecution(budget: budget, limits: limits,
            context: .init(operation: .conversion, entry: .ordinary, stage: .request))
        return try evaluateValidated(feature: feature, context: context, using: &execution)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): The feature dispatcher uses this entry
    // for the selected original source construction. Existing request/expression
    // or staged feature branches still need their own direct contract; this
    // binding must not be counted as complete whole-feature U1 accounting.
    package func evaluateValidated(feature: FeatureNode, context: EvaluationContext,
        using execution: inout OriginalQueryExecution) throws -> ValidatedFeatureEvaluation {
        do {
            return try evaluateBridgeSurface(feature: feature, context: context, using: &execution)
        } catch {
            let retained = OriginalQueryFailure.published(error, context: execution.context,
                tolerance: context.tolerance)
            guard let classification = OriginalQueryFailure.classification(of: retained) else {
                throw retained
            }
            throw OriginalQueryFailure.contextualizing(retained, classification: KernelError.wrapping(
                classification, phase: .evaluation, featureID: feature.id, tolerance: context.tolerance))
        }
    }

    @inline(never)
    private func evaluateBridgeSurface(
        feature: FeatureNode,
        context: EvaluationContext, using execution: inout OriginalQueryExecution
    ) throws -> ValidatedFeatureEvaluation {
        guard case let .bridgeSurface(bridge) = feature.operation else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                message: "BridgeSurfaceFeatureEvaluator requires a bridge surface feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try bridge.validate(tolerance: context.tolerance)
        }
        guard feature.inputs == bridge.sourceInputs,
              feature.outputs.map { $0.role } == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph(
                "Bridge surface requires its boundary source inputs and one sheet output."
            )
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context,
            featureID: feature.id,
            tolerance: context.tolerance
        )

        return try constructBridgeSurface(bridge, feature: feature, context: context,
            using: &execution)
    }

    @inline(never)
    private func constructBridgeSurface(
        _ bridge: BridgeSurfaceFeature,
        feature: FeatureNode,
        context: EvaluationContext,
        using execution: inout OriginalQueryExecution
    ) throws -> ValidatedFeatureEvaluation {
        let prepared = try prepareBridgeSurface(bridge, feature: feature, context: context,
            using: &execution)
        let candidate = try surfaceEvaluator.evaluateValidated(
            feature: FeatureNode(
                id: feature.id,
                name: feature.name,
                operation: .bSplineSurface(prepared.surfaceFeature),
                outputs: feature.outputs,
                isSuppressed: feature.isSuppressed
            ),
            context: context
        )
        if prepared.constrained || bridge.startWall != nil || bridge.endWall != nil {
            guard let wallTrimmer else {
                throw KernelError(phase: .evaluation, code: .dependencyUnavailable, featureID: feature.id,
                    tolerance: context.tolerance, message: "Finite bridge wall clipping requires the kernel trim port.")
            }
            return try ValidatedFeatureEvaluation(validating:
                wallTrimmer.trim(feature: feature, candidate: candidate.result, context: context, using: &execution),
                tolerance: context.tolerance, using: &execution)
        }
        return candidate
    }

    @inline(never)
    private func prepareBridgeSurface(
        _ bridge: BridgeSurfaceFeature,
        feature: FeatureNode,
        context: EvaluationContext,
        using execution: inout OriginalQueryExecution
    ) throws -> (surfaceFeature: BSplineSurfaceFeature, constrained: Bool) {
        let bodyID = try context.bodyID(generatedBy: bridge.targetFeatureID)
        let endBodyID = try context.bodyID(generatedBy: bridge.endBoundary.subshapeID.featureID)
        guard let body = context.brep.bodies[bodyID],
              let endBody = context.brep.bodies[endBodyID] else {
            throw TopologyError.missingReference("Bridge surface source body is missing.")
        }
        let startEdgeID = try resolveBoundaryEdge(
            bridge.startBoundary,
            featureID: feature.id,
            context: context
        )
        let endEdgeID = try resolveBoundaryEdge(
            bridge.endBoundary,
            featureID: feature.id,
            context: context
        )
        guard (startEdgeID != endEdgeID || bridge.startTransform != bridge.endTransform),
              try boundaryLoopResolver.loop(
                startingAt: startEdgeID,
                in: body,
                model: context.brep
              , using: &execution) != nil,
              try boundaryLoopResolver.loop(
                startingAt: endEdgeID,
                in: endBody,
                model: context.brep
              , using: &execution) != nil else {
            throw KernelError.unsupportedEvaluation(
                featureID: feature.id,
                tolerance: context.tolerance,
                message: "Bridge surface requires two distinct edges on the source body's open boundary."
            )
        }

        var startBoundary = try boundaryCurveResolver.curve(
            edgeID: startEdgeID,
            followsStoredDirection: true,
            model: context.brep,
            tolerance: context.tolerance,
            featureID: feature.id
        )
        var endBoundary = try boundaryCurveResolver.curve(
            edgeID: endEdgeID,
            followsStoredDirection: true,
            model: context.brep,
            tolerance: context.tolerance,
            featureID: feature.id
        )
        if let transform = bridge.startTransform {
            startBoundary = try transform.applying(to: startBoundary, tolerance: context.tolerance)
        }
        if let transform = bridge.endTransform {
            endBoundary = try transform.applying(to: endBoundary, tolerance: context.tolerance)
        }
        if bridge.endOrientation == .reversed {
            endBoundary = try endBoundary.reversed(tolerance: context.tolerance)
        }
        let constrained = bridge.startContinuity != .positional || bridge.endContinuity != .positional
            || bridge.startTension != 1 || bridge.endTension != 1 || bridge.width != nil
        let surface: BSplineSurface3D
        if constrained {
            let firstWall = try boundaryWall(edgeID: startEdgeID, explicit: bridge.startWall,
                body: body, transform: bridge.startTransform, followsStoredDirection: true,
                featureID: feature.id, context: context)
            let lastWall = try boundaryWall(edgeID: endEdgeID, explicit: bridge.endWall,
                body: endBody, transform: bridge.endTransform,
                followsStoredDirection: bridge.endOrientation != .reversed,
                featureID: feature.id, context: context)
            surface = try ConstrainedBridgeSurfaceBuilder().build(start: startBoundary, end: endBoundary,
                startWall: firstWall.surface, endWall: lastWall.surface,
                startContinuity: bridge.startContinuity, endContinuity: bridge.endContinuity,
                startTension: bridge.startTension, endTension: bridge.endTension, width: bridge.width,
                startWallBoundary: firstWall.boundary, endWallBoundary: lastWall.boundary,
                tolerance: context.tolerance, using: &execution)
        } else {
            surface = try surfaceBuilder.build(startBoundary: startBoundary, endBoundary: endBoundary,
                tolerance: context.tolerance, using: &execution)
        }
        return (BSplineSurfaceFeature(surface: surface, material: body.material), constrained)
    }

    private func boundaryWall(edgeID: EdgeID, explicit: StableSubshapeReference?, body: Body,
                              transform: AffineTransform3D?, followsStoredDirection: Bool,
                              featureID: FeatureID, context: EvaluationContext) throws
        -> (surface: Surface3D, boundary: SurfaceParameterCurve) {
        let faceID: FaceID
        if let explicit {
            let reference = try subshapeResolver.topologyReference(for: explicit, model: context.brep,
                subshapes: context.subshapes, lineage: context.lineage, tolerance: context.tolerance)
            guard case let .face(value) = reference else {
                throw KernelError(phase: .evaluation, code: .missingReference, featureID: featureID,
                    tolerance: context.tolerance, message: "A bridge wall reference must resolve to a live source face.")
            }
            faceID = value
        } else {
            let incident = body.shellIDs.flatMap { context.brep.shells[$0]?.faceIDs ?? [] }.filter { faceID in
                context.brep.faces[faceID]?.loops.contains { loopID in
                    context.brep.loops[loopID]?.coedges.contains { $0.edgeID == edgeID } == true
                } == true
            }
            guard incident.count == 1, let value = incident.first else {
                throw KernelError(phase: .evaluation, code: .ambiguousSelection, featureID: featureID,
                    tolerance: context.tolerance, message: "A constrained bridge requires one incident wall per source boundary.")
            }
            faceID = value
        }
        guard let face = context.brep.faces[faceID], let surface = context.brep.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("A bridge source wall is missing.")
        }
        let placed: Surface3D
        if let transform {
            placed = .procedural(.originalImage(try OriginalImageSurface3D(source: surface,
                transform: transform, tolerance: context.tolerance)))
        } else { placed = surface }
        let uses = face.loops.flatMap { context.brep.loops[$0]?.edges ?? [] }
            .filter { $0.edgeID == edgeID }
        let boundary: SurfaceParameterCurve
        if uses.count == 1, let coedge = uses.first, let original = coedge.surfaceParameterCurve {
            boundary = (coedge.orientation == .forward) == followsStoredDirection
                ? original : try original.reversed(tolerance: context.tolerance)
        } else if uses.isEmpty {
            guard let edge = context.brep.edges[edgeID], let trim = edge.trim,
                  let curve = context.brep.geometry.curves[edge.curveID] else {
                throw TopologyError.missingReference("An explicit bridge wall requires the retained original boundary trim.")
            }
            let original: Curve3D
            if let transform {
                original = .affineImage(try AffineImageCurve3D(source: curve,
                    transform: transform, tolerance: context.tolerance))
            } else { original = curve }
            boundary = try ExactFacePcurveBuilder().surfaceParameterCurve(for: original,
                startParameter: followsStoredDirection ? trim.startParameter : trim.endParameter,
                endParameter: followsStoredDirection ? trim.endParameter : trim.startParameter,
                on: placed, tolerance: context.tolerance)
        } else {
            throw KernelError(phase: .evaluation, code: .ambiguousSelection, featureID: featureID,
                tolerance: context.tolerance, message: "A bridge wall has no unique original boundary coedge use.")
        }
        try boundary.validate(on: placed, tolerance: context.tolerance)
        return (placed, boundary)
    }

    private func resolveBoundaryEdge(
        _ reference: StableSubshapeReference,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EdgeID {
        let topology = try subshapeResolver.topologyReference(
            for: reference,
            model: context.brep,
            subshapes: context.subshapes,
            lineage: context.lineage,
            tolerance: context.tolerance
        )
        guard case let .edge(edgeID) = topology else {
            throw KernelError(
                phase: .validation,
                code: .missingReference,
                featureID: featureID,
                subshapeID: reference.subshapeID,
                tolerance: context.tolerance,
                message: "Bridge surface source reference no longer resolves to an edge."
            )
        }
        return edgeID
    }
}
