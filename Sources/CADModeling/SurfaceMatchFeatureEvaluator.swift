import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct SurfaceMatchFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let identityBuilder: any CarriedTopologyIdentityBuilding
    private let editor: any RectangularSurfaceSheetEditing
    private let patchBuilder: ExactRectangularBSplineSurfacePatchBuilder

    public init() {
        identityBuilder = DefaultCarriedTopologyIdentityBuilder()
        editor = DefaultRectangularSurfaceSheetEditor()
        patchBuilder = ExactRectangularBSplineSurfacePatchBuilder()
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
        guard case let .surfaceMatch(match) = feature.operation else {
            throw kernelError(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Surface match evaluator requires a surfaceMatch feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try match.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context.brep,
            featureID: feature.id,
            tolerance: context.tolerance
        )

        let sourceBodyID = try context.bodyID(generatedBy: match.source.featureID)
        let targetBodyID = try context.bodyID(generatedBy: match.target.featureID)
        guard sourceBodyID != targetBodyID else {
            throw kernelError(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Surface match source and target must resolve to different bodies."
            )
        }
        let replacedSubshapeIDs = try [sourceBodyID, targetBodyID].reduce(
            into: Set<SubshapeID>()
        ) { result, bodyID in
            result.formUnion(try BodyTopologyScope(
                bodyID: bodyID,
                model: context.brep
            ).subshapeIDs(in: context.subshapes))
        }

        var sourceModel = try BRepBodySubmodelExtractor().extract(
            bodyIDs: [sourceBodyID],
            from: context.brep
        )
        let targetModel = try BRepBodySubmodelExtractor().extract(
            bodyIDs: [targetBodyID],
            from: context.brep
        )
        let sourceFace = try singleFaceSheet(
            bodyID: sourceBodyID,
            model: sourceModel,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let targetFace = try singleFaceSheet(
            bodyID: targetBodyID,
            model: targetModel,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let sourceBounds = try editor.bounds(
            bodyID: sourceBodyID,
            model: sourceModel,
            tolerance: context.tolerance
        )
        let targetBounds = try editor.bounds(
            bodyID: targetBodyID,
            model: targetModel,
            tolerance: context.tolerance
        )
        try validateParameter(
            match.sourceParameter,
            bounds: sourceBounds,
            owner: "source",
            featureID: feature.id,
            tolerance: context.tolerance
        )
        try validateParameter(
            match.targetParameter,
            bounds: targetBounds,
            owner: "target",
            featureID: feature.id,
            tolerance: context.tolerance
        )

        let transform = try frameTransform(
            sourceSurface: sourceFace.surface,
            sourceParameter: match.sourceParameter,
            targetSurface: targetFace.surface,
            targetParameter: match.targetParameter,
            alignment: match.normalAlignment,
            tolerance: context.tolerance
        )
        let patch = try patchBuilder.build(
            surface: sourceFace.surface,
            lowerU: sourceBounds.lowerU,
            upperU: sourceBounds.upperU,
            lowerV: sourceBounds.lowerV,
            upperV: sourceBounds.upperV,
            tolerance: context.tolerance
        )
        let outputParameter = try patch.parameter(
            for: match.sourceParameter,
            tolerance: context.tolerance
        )
        let transformedSurface = Surface3D.bSpline(try transform.applying(
            to: patch.surface,
            tolerance: context.tolerance
        ))
        let transformedBounds = RectangularSurfaceParameterBounds(
            lowerU: patch.uMapping.targetLower,
            upperU: patch.uMapping.targetUpper,
            lowerV: patch.vMapping.targetLower,
            upperV: patch.vMapping.targetUpper
        )
        try editor.replaceSurface(
            featureID: feature.id,
            bodyID: sourceBodyID,
            with: transformedSurface,
            bounds: transformedBounds,
            model: &sourceModel,
            tolerance: context.tolerance
        )
        try sourceModel.validate(level: .exact, tolerance: context.tolerance)
        try verify(
            outputSurface: transformedSurface,
            outputParameter: outputParameter,
            targetSurface: targetFace.surface,
            targetParameter: match.targetParameter,
            alignment: match.normalAlignment,
            continuity: match.continuity,
            featureID: feature.id,
            tolerance: context.tolerance
        )

        let identity = try identityBuilder.identity(
            featureID: feature.id,
            bodyID: sourceBodyID,
            model: sourceModel,
            context: context
        )
        let lineage = mergedFaceLineage(
            identity.lineage,
            targetFaceID: targetFace.id,
            context: context
        )
        let model = try BRepBodyModelReplacer().replacing(
            bodyIDs: [sourceBodyID, targetBodyID],
            with: sourceModel,
            in: context.brep
        )
        try model.validate(level: .exact, tolerance: context.tolerance)
        return EvaluationResult(
            brep: model,
            subshapes: identity.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: lineage
        )
    }

    private func singleFaceSheet(
        bodyID: BodyID,
        model: BRepModel,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> (id: FaceID, surface: Surface3D) {
        guard let body = model.bodies[bodyID],
              body.kind == .sheet,
              body.shellIDs.count == 1,
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID],
              shell.faceIDs.count == 1,
              let faceID = shell.faceIDs.first,
              let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID] else {
            throw kernelError(
                .unsupportedCapability,
                featureID: featureID,
                tolerance: tolerance,
                "Exact surface match requires two single-face exact sheet bodies."
            )
        }
        return (faceID, surface)
    }

    private func validateParameter(
        _ parameter: SurfaceParameter,
        bounds: RectangularSurfaceParameterBounds,
        owner: String,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws {
        let scale = max(
            abs(bounds.lowerU),
            abs(bounds.upperU),
            abs(bounds.lowerV),
            abs(bounds.upperV),
            1.0
        )
        let parameterTolerance = max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 256.0
        )
        guard parameter.u >= bounds.lowerU - parameterTolerance,
              parameter.u <= bounds.upperU + parameterTolerance,
              parameter.v >= bounds.lowerV - parameterTolerance,
              parameter.v <= bounds.upperV + parameterTolerance else {
            throw kernelError(
                .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                "Surface match \(owner) parameter must lie inside the trimmed sheet."
            )
        }
    }

    private func frameTransform(
        sourceSurface: Surface3D,
        sourceParameter: SurfaceParameter,
        targetSurface: Surface3D,
        targetParameter: SurfaceParameter,
        alignment: SurfaceNormalAlignment,
        tolerance: ModelingTolerance
    ) throws -> ExactPatternTransform {
        let sourceFrame = try sourceSurface.uvnFrame(
            atU: sourceParameter.u,
            v: sourceParameter.v,
            tolerance: tolerance
        )
        let targetFrame = try targetSurface.uvnFrame(
            atU: targetParameter.u,
            v: targetParameter.v,
            tolerance: tolerance
        )
        let targetU = targetFrame.u
        let targetV: Vector3D
        let targetN: Vector3D
        switch alignment {
        case .aligned:
            targetV = targetFrame.v
            targetN = targetFrame.normal
        case .opposed:
            targetV = -targetFrame.v
            targetN = -targetFrame.normal
        }
        func mapped(_ vector: Vector3D) -> Vector3D {
            targetU * sourceFrame.u.dot(vector)
                + targetV * sourceFrame.v.dot(vector)
                + targetN * sourceFrame.normal.dot(vector)
        }
        let basisX = mapped(.unitX)
        let basisY = mapped(.unitY)
        let basisZ = mapped(.unitZ)
        let rotatedSource = Point3D.origin
            + basisX * sourceFrame.position.x
            + basisY * sourceFrame.position.y
            + basisZ * sourceFrame.position.z
        return ExactPatternTransform(
            basisX: basisX,
            basisY: basisY,
            basisZ: basisZ,
            translation: targetFrame.position - rotatedSource
        )
    }

    private func verify(
        outputSurface: Surface3D,
        outputParameter: SurfaceParameter,
        targetSurface: Surface3D,
        targetParameter: SurfaceParameter,
        alignment: SurfaceNormalAlignment,
        continuity: SurfaceContinuityLevel,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws {
        let targetOrientation: SurfaceFrameOrientation = alignment == .aligned
            ? .forward
            : .reversed
        let result = try SurfaceContinuityEvaluator(
            modelingTolerance: tolerance
        ).evaluate(SurfaceContinuityRequest(
            samplePairs: [SurfaceContinuitySamplePair(
                first: SurfaceContinuityTarget(
                    surface: outputSurface,
                    u: outputParameter.u,
                    v: outputParameter.v
                ),
                second: SurfaceContinuityTarget(
                    surface: targetSurface,
                    u: targetParameter.u,
                    v: targetParameter.v,
                    orientation: targetOrientation
                )
            )],
            requiredLevel: continuity,
            tolerances: .standard(modelingTolerance: tolerance)
        ))
        guard result.isSatisfied else {
            throw KernelError(
                phase: .geometry,
                code: .conflictingConstraints,
                featureID: featureID,
                residual: max(
                    result.deviation.maximumPositionDistance,
                    result.deviation.maximumNormalAngle,
                    result.deviation.maximumPrincipalCurvatureDistance
                ),
                tolerance: tolerance,
                message: "Surface match could not satisfy the requested exact continuity."
            )
        }
    }

    private func mergedFaceLineage(
        _ sourceLineage: [SubshapeID: TopologyLineage],
        targetFaceID: FaceID,
        context: EvaluationContext
    ) -> [SubshapeID: TopologyLineage] {
        var result = sourceLineage
        let targetParents = context.subshapeIDs(for: .face(targetFaceID))
        guard targetParents.isEmpty == false,
              let output = result.keys.first(where: {
                  $0.role == GeneratedSubshapeRole.face.rawValue
              }),
              let current = result[output] else {
            return result
        }
        let parents = Array(Set(current.parents).union(targetParents)).sorted()
        let relation: TopologyLineageRelation = switch parents.count {
        case 0: .generated
        case 1: .preserved
        default: .merged
        }
        result[output] = TopologyLineage(
            output: output,
            parents: parents,
            relation: relation
        )
        return result
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
