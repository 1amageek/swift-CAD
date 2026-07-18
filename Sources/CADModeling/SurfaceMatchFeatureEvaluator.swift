import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct SurfaceMatchFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let identityBuilder: any CarriedTopologyIdentityBuilding
    private let geometryRebuilder: any PlanarBodyGeometryRebuilding
    private let editor: any RectangularPlanarSheetEditing

    public init() {
        self.identityBuilder = DefaultCarriedTopologyIdentityBuilder()
        self.geometryRebuilder = DefaultPlanarBodyGeometryRebuilder()
        self.editor = DefaultRectangularPlanarSheetEditor()
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
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try match.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context.brep,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let sourceBodyID = try bodyID(
            featureID: match.source.featureID,
            owner: "source",
            matchFeatureID: feature.id,
            context: context
        )
        let targetBodyID = try bodyID(
            featureID: match.target.featureID,
            owner: "target",
            matchFeatureID: feature.id,
            context: context
        )
        guard sourceBodyID != targetBodyID else {
            throw kernelError(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Surface match source and target must resolve to different bodies."
            )
        }
        let replacedSubshapeIDs = try [sourceBodyID, targetBodyID].reduce(into: Set<SubshapeID>()) { result, bodyID in
            result.formUnion(try BodyTopologyScope(
                bodyID: bodyID,
                model: context.brep
            ).subshapeIDs(in: context.subshapes))
        }
        var sourceModel = try BRepBodySubmodelExtractor().extract(bodyIDs: [sourceBodyID], from: context.brep)
        let targetModel = try BRepBodySubmodelExtractor().extract(bodyIDs: [targetBodyID], from: context.brep)
        let sourceFace = try planarFace(bodyID: sourceBodyID, model: sourceModel, featureID: feature.id, tolerance: context.tolerance)
        let targetFace = try planarFace(bodyID: targetBodyID, model: targetModel, featureID: feature.id, tolerance: context.tolerance)
        try validateParameter(
            match.sourceParameter,
            bodyID: sourceBodyID,
            model: sourceModel,
            owner: "source",
            featureID: feature.id,
            tolerance: context.tolerance
        )
        try validateParameter(
            match.targetParameter,
            bodyID: targetBodyID,
            model: targetModel,
            owner: "target",
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let transform = try frameTransform(
            sourcePlane: sourceFace.plane,
            sourceParameter: match.sourceParameter,
            targetPlane: targetFace.plane,
            targetParameter: match.targetParameter,
            alignment: match.normalAlignment,
            tolerance: context.tolerance
        )
        for vertexID in sourceModel.vertices.keys {
            guard var vertex = sourceModel.vertices[vertexID] else {
                throw TopologyError.missingReference("Surface match source vertex is missing.")
            }
            vertex.point = transform.applying(to: vertex.point)
            sourceModel.vertices[vertexID] = vertex
        }
        try geometryRebuilder.rebuild(
            featureID: feature.id,
            bodyID: sourceBodyID,
            in: &sourceModel,
            tolerance: context.tolerance
        )
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &sourceModel, tolerance: context.tolerance)
        try sourceModel.validate(level: .exact, tolerance: context.tolerance)
        try verify(
            model: sourceModel,
            bodyID: sourceBodyID,
            targetPlane: targetFace.plane,
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

    private func bodyID(
        featureID: FeatureID,
        owner: String,
        matchFeatureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        try context.bodyID(generatedBy: featureID)
    }

    private func planarFace(
        bodyID: BodyID,
        model: BRepModel,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> (id: FaceID, plane: Plane3D) {
        guard let body = model.bodies[bodyID],
              body.kind == .sheet,
              body.shellIDs.count == 1,
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID],
              shell.faceIDs.count == 1,
              let faceID = shell.faceIDs.first,
              let face = model.faces[faceID],
              case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else {
            throw kernelError(
                .unsupportedCapability,
                featureID: featureID,
                tolerance: tolerance,
                "Exact surface match currently requires two single-face planar sheets."
            )
        }
        return (faceID, plane)
    }

    private func validateParameter(
        _ parameter: SurfaceParameter,
        bodyID: BodyID,
        model: BRepModel,
        owner: String,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws {
        let bounds = try editor.bounds(bodyID: bodyID, model: model, tolerance: tolerance)
        guard parameter.u >= bounds.lowerU - tolerance.distance,
              parameter.u <= bounds.upperU + tolerance.distance,
              parameter.v >= bounds.lowerV - tolerance.distance,
              parameter.v <= bounds.upperV + tolerance.distance else {
            throw kernelError(
                .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                "Surface match \(owner) parameter must lie inside the trimmed sheet."
            )
        }
    }

    private func frameTransform(
        sourcePlane: Plane3D,
        sourceParameter: SurfaceParameter,
        targetPlane: Plane3D,
        targetParameter: SurfaceParameter,
        alignment: SurfaceNormalAlignment,
        tolerance: ModelingTolerance
    ) throws -> ExactPatternTransform {
        let sourceSurface = Surface3D.plane(sourcePlane)
        let targetSurface = Surface3D.plane(targetPlane)
        let sourceFrame = try sourceSurface.differentialGeometry(
            atU: sourceParameter.u,
            v: sourceParameter.v,
            tolerance: tolerance
        )
        let targetFrame = try targetSurface.differentialGeometry(
            atU: targetParameter.u,
            v: targetParameter.v,
            tolerance: tolerance
        )
        let sourceU = try sourceFrame.tangentU.normalized(tolerance: tolerance.distance)
        let sourceV = try sourceFrame.tangentV.normalized(tolerance: tolerance.distance)
        let sourceN = try sourceFrame.normal.normalized(tolerance: tolerance.distance)
        let targetU = try targetFrame.tangentU.normalized(tolerance: tolerance.distance)
        let targetV: Vector3D
        let targetN: Vector3D
        switch alignment {
        case .aligned:
            targetV = try targetFrame.tangentV.normalized(tolerance: tolerance.distance)
            targetN = try targetFrame.normal.normalized(tolerance: tolerance.distance)
        case .opposed:
            targetV = try (-targetFrame.tangentV).normalized(tolerance: tolerance.distance)
            targetN = try (-targetFrame.normal).normalized(tolerance: tolerance.distance)
        }
        func mapped(_ vector: Vector3D) -> Vector3D {
            targetU * sourceU.dot(vector)
                + targetV * sourceV.dot(vector)
                + targetN * sourceN.dot(vector)
        }
        let basisX = mapped(.unitX)
        let basisY = mapped(.unitY)
        let basisZ = mapped(.unitZ)
        let rotatedX = basisX * sourceFrame.position.x
        let rotatedY = basisY * sourceFrame.position.y
        let rotatedZ = basisZ * sourceFrame.position.z
        let rotatedSource = Point3D.origin + (rotatedX + rotatedY + rotatedZ)
        return ExactPatternTransform(
            basisX: basisX,
            basisY: basisY,
            basisZ: basisZ,
            translation: targetFrame.position - rotatedSource
        )
    }

    private func verify(
        model: BRepModel,
        bodyID: BodyID,
        targetPlane: Plane3D,
        alignment: SurfaceNormalAlignment,
        continuity: SurfaceContinuityLevel,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws {
        let result = try planarFace(bodyID: bodyID, model: model, featureID: featureID, tolerance: tolerance)
        let expectedNormal = alignment == .aligned ? targetPlane.normal : -targetPlane.normal
        let normalDot = min(1.0, max(-1.0, result.plane.normal.dot(expectedNormal)))
        let normalResidual = acos(normalDot)
        let positionResidual = model.vertices.values.map { vertex in
            abs((vertex.point - targetPlane.origin).dot(targetPlane.normal))
        }.max() ?? 0.0
        guard positionResidual <= tolerance.distance else {
            throw verificationError(
                featureID: featureID,
                residual: positionResidual,
                tolerance: tolerance,
                message: "Surface match failed positional continuity verification."
            )
        }
        if continuity >= .tangentPlane, normalResidual > tolerance.angle {
            throw verificationError(
                featureID: featureID,
                residual: normalResidual,
                tolerance: tolerance,
                message: "Surface match failed tangent-plane continuity verification."
            )
        }
        if continuity >= .curvature {
            let curvatureResidual = 0.0
            guard curvatureResidual <= tolerance.distance else {
                throw verificationError(
                    featureID: featureID,
                    residual: curvatureResidual,
                    tolerance: tolerance,
                    message: "Surface match failed curvature continuity verification."
                )
            }
        }
    }

    private func mergedFaceLineage(
        _ sourceLineage: [SubshapeID: TopologyLineage],
        targetFaceID: FaceID,
        context: EvaluationContext
    ) -> [SubshapeID: TopologyLineage] {
        var result = sourceLineage
        let targetParents = subshapeIDs(for: .face(targetFaceID), context: context)
        guard targetParents.isEmpty == false,
              let output = result.keys.first(where: { $0.role == GeneratedSubshapeRole.face.rawValue }),
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

    private func subshapeIDs(
        for reference: TopologyReference,
        context: EvaluationContext
    ) -> [SubshapeID] {
        context.subshapeIDs(for: reference)
    }

    private func verificationError(
        featureID: FeatureID,
        residual: Double,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .conflictingConstraints,
            featureID: featureID,
            residual: residual,
            tolerance: tolerance,
            message: message
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
