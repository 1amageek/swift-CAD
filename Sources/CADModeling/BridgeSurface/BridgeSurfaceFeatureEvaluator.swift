import CADCore
import CADGeometry
import CADIR
import CADTopology

// FIXME(INCOMPLETE_IMPLEMENTATION): This implements G0 boundary bridging only.
// CADKernel and the editor Boundary Bridge command use this evaluator; full
// Bridge Surface requires width, tension, G2/chamfer and wall-trim construction.
public struct BridgeSurfaceFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let surfaceEvaluator: BSplineSurfaceFeatureEvaluator
    private let surfaceBuilder: any RuledBSplineSurfaceBuilding
    private let subshapeResolver = StableSubshapeResolver()
    private let boundaryLoopResolver = OpenBoundaryLoopResolver()
    private let boundaryCurveResolver = ExactBoundaryCurveResolver()

    public init(
        surfaceEvaluator: BSplineSurfaceFeatureEvaluator = BSplineSurfaceFeatureEvaluator(),
        surfaceBuilder: any RuledBSplineSurfaceBuilding = ExactRuledBSplineSurfaceBuilder()
    ) {
        self.surfaceEvaluator = surfaceEvaluator
        self.surfaceBuilder = surfaceBuilder
    }

    public func evaluate(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        do {
            return try evaluateBridgeSurface(feature: feature, context: context)
        } catch {
            throw KernelError.wrapping(
                error, phase: .evaluation, featureID: feature.id,
                tolerance: context.tolerance
            )
        }
    }

    private func evaluateBridgeSurface(
        feature: FeatureNode,
        context: EvaluationContext
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
              feature.outputs.map(\.role) == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph(
                "Bridge surface requires its boundary source inputs and one sheet output."
            )
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context,
            featureID: feature.id,
            tolerance: context.tolerance
        )

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
        guard startEdgeID != endEdgeID,
              boundaryLoopResolver.loop(
                startingAt: startEdgeID,
                in: body,
                model: context.brep
              ) != nil,
              boundaryLoopResolver.loop(
                startingAt: endEdgeID,
                in: endBody,
                model: context.brep
              ) != nil else {
            throw KernelError.unsupportedEvaluation(
                featureID: feature.id,
                tolerance: context.tolerance,
                message: "Bridge surface requires two distinct edges on the source body's open boundary."
            )
        }

        let startBoundary = try boundaryCurveResolver.curve(
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
        if bridge.endOrientation == .reversed {
            endBoundary = try endBoundary.reversed(tolerance: context.tolerance)
        }
        let surface = try surfaceBuilder.build(
            startBoundary: startBoundary,
            endBoundary: endBoundary,
            tolerance: context.tolerance
        )
        return try surfaceEvaluator.evaluateValidated(
            feature: FeatureNode(
                id: feature.id,
                name: feature.name,
                operation: .bSplineSurface(BSplineSurfaceFeature(
                    surface: surface,
                    material: body.material
                )),
                outputs: feature.outputs,
                isSuppressed: feature.isSuppressed
            ),
            context: context
        )
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
