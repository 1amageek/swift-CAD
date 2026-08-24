import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct SurfaceTrimFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let targetResolver: any SurfaceOperationTargetResolving
    private let targetValidator: any SingleFaceSheetSurfaceOperationTargetValidating
    private let rectangularEditor: any RectangularSurfaceSheetEditing
    private let loopValidator: ExactSurfaceTrimLoopValidator
    private let sewer: any BRepSewing

    public init(sewer: any BRepSewing) {
        targetResolver = DefaultSurfaceOperationTargetResolver()
        targetValidator = DefaultSingleFaceSheetSurfaceOperationTargetValidator()
        rectangularEditor = DefaultRectangularSurfaceSheetEditor()
        loopValidator = ExactSurfaceTrimLoopValidator()
        self.sewer = sewer
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
        try FeatureEvaluationBoundary.evaluateValidated(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try evaluateUnvalidated(feature: feature, context: context)
        }
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard case let .surfaceTrim(trim) = feature.operation else {
            throw kernelError(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Surface trim evaluator requires a surfaceTrim feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try trim.validate(tolerance: context.tolerance)
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let target = try targetResolver.resolve(
            trim.target,
            featureID: feature.id,
            context: context
        )
        let sourceBodyID = target.bodyID
        let replacedSubshapeIDs = try BodyTopologyScope(
            bodyID: sourceBodyID,
            model: context.brep
        ).subshapeIDs(in: context.subshapes)
        let source = try sourceSheet(
            target: target,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let sourceBounds = try rectangularEditor.bounds(
            bodyID: sourceBodyID,
            model: context.brep,
            tolerance: context.tolerance
        )
        let validated = try loopValidator.validate(
            trim.loops,
            on: source.surface,
            inside: sourceBounds,
            tolerance: context.tolerance
        )
        let sewingLoops = try validated.loops.enumerated().map { loopIndex, loop in
            BRepSewingLoop(
                stableID: "surfaceTrim:loop:\(loopIndex)",
                role: loop.role == .outer ? .outer : .inner,
                edges: try loop.parameterCurves.enumerated().map { edgeIndex, pcurve in
                    try sewingEdge(
                        stableID: "surfaceTrim:loop:\(loopIndex):edge:\(edgeIndex)",
                        pcurve: pcurve,
                        surface: source.surface,
                        tolerance: context.tolerance
                    )
                }
            )
        }
        let sewn = try sewer.sew(BRepSewingRequest(
            featureID: feature.id,
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "surfaceTrim:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "surfaceTrim:face",
                    surface: source.surface,
                    orientation: source.orientation,
                    loops: sewingLoops,
                    parentSubshapeIDs: context.subshapeIDs(
                        for: .face(source.faceID)
                    )
                )],
                orientation: source.shellOrientation
            )],
            bodyParentSubshapeIDs: context.subshapeIDs(
                for: .body(sourceBodyID)
            )
        ), tolerance: context.tolerance)
        let model = try BRepBodyModelReplacer().replacing(
            bodyID: sourceBodyID,
            with: sewn.bodyID,
            from: sewn.brep,
            in: context.brep
        )
        try model.validate(level: .exact, tolerance: context.tolerance)
        return EvaluationResult(
            brep: model,
            subshapes: sewn.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: sewn.lineage
        )
    }

    private func sourceSheet(
        target: ResolvedSurfaceOperationTarget,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> (
        faceID: FaceID,
        surface: Surface3D,
        orientation: Orientation,
        shellOrientation: Orientation
    ) {
        try targetValidator.validate(
            target,
            operation: "Surface trim",
            featureID: featureID,
            tolerance: tolerance
        )
        return (
            target.faceID,
            target.surface,
            target.face.orientation,
            target.shell.orientation
        )
    }

    private func sewingEdge(
        stableID: String,
        pcurve: SurfaceParameterCurve,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let startParameter = try pcurve.startParameter(tolerance: tolerance)
        let endParameter = try pcurve.endParameter(tolerance: tolerance)
        let startPoint = try surface.point(
            u: startParameter.u,
            v: startParameter.v,
            tolerance: tolerance
        )
        let endPoint = try surface.point(
            u: endParameter.u,
            v: endParameter.v,
            tolerance: tolerance
        )
        return BRepSewingEdge(
            stableID: stableID,
            curve: .surfaceLift(SurfaceLiftCurve3D(
                surface: surface,
                parameterCurve: pcurve
            )),
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: startPoint,
            endPoint: endPoint,
            surfaceParameterCurve: pcurve
        )
    }

    private func kernelError(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .evaluation,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }
}
