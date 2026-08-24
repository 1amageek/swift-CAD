import Foundation
import CADCore
import CADIR
import CADTopology

public struct FaceDraftFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving
    private let identityBuilder: any CarriedTopologyIdentityBuilding
    private let geometryRebuilder: any PlanarBodyGeometryRebuilding
    private let constraintSolver: any PlanarDraftConstraintSolving

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()
    ) {
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
        identityBuilder = DefaultCarriedTopologyIdentityBuilder()
        geometryRebuilder = DefaultPlanarBodyGeometryRebuilder()
        constraintSolver = DefaultPlanarDraftConstraintSolver()
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
            try context.tolerance.validate()
            let result = try evaluateFaceDraft(feature: feature, context: context)
            return try ValidatedFeatureEvaluation(
                validating: result,
                tolerance: context.tolerance
            )
        } catch {
            throw KernelError.wrapping(
                error,
                phase: .evaluation,
                featureID: feature.id,
                tolerance: context.tolerance
            )
        }
    }

    private func evaluateFaceDraft(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard case let .faceDraft(faceDraft) = feature.operation else {
            throw kernelError(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Face draft evaluator requires a faceDraft feature."
            )
        }
        do {
            try faceDraft.validate()
        } catch {
            throw KernelError.wrapping(
                error,
                phase: .validation,
                featureID: feature.id,
                tolerance: context.tolerance
            )
        }
        do {
            try FeatureEvaluationBoundary.validateExactInput(
                context,
                featureID: feature.id,
                tolerance: context.tolerance
            )
        } catch {
            throw KernelError.wrapping(
                error,
                phase: .topology,
                featureID: feature.id,
                tolerance: context.tolerance
            )
        }

        let angle = try resolvedAngle(
            faceDraft.angle,
            featureID: feature.id,
            context: context
        )
        let bodyID = try context.bodyID(generatedBy: faceDraft.target.featureID)
        let replacedSubshapeIDs = try BodyTopologyScope(
            bodyID: bodyID,
            model: context.brep
        ).subshapeIDs(in: context.subshapes)
        var targetFaceSubshapeIDs: [FaceID: SubshapeID] = [:]
        for stableReference in faceDraft.faces {
            let faceID = try targetFaceID(
                for: stableReference,
                featureID: feature.id,
                context: context
            )
            guard targetFaceSubshapeIDs[faceID] == nil else {
                throw kernelError(
                    .invalidInput,
                    featureID: feature.id,
                    subshapeID: stableReference.subshapeID,
                    tolerance: context.tolerance,
                    "Face draft selections resolve to the same face."
                )
            }
            targetFaceSubshapeIDs[faceID] = stableReference.subshapeID
        }
        let neutralFaceID = try targetFaceID(
            for: faceDraft.neutralFace,
            featureID: feature.id,
            context: context
        )
        guard targetFaceSubshapeIDs[neutralFaceID] == nil else {
            throw kernelError(
                .invalidInput,
                featureID: feature.id,
                subshapeID: faceDraft.neutralFace.subshapeID,
                tolerance: context.tolerance,
                "Face draft neutral face must be distinct from its target faces."
            )
        }

        var model = context.brep
        try draftFaces(
            targetFaceSubshapeIDs,
            neutralFaceID: neutralFaceID,
            angle: angle,
            bodyID: bodyID,
            featureID: feature.id,
            model: &model,
            tolerance: context.tolerance
        )
        try geometryRebuilder.rebuild(
            featureID: feature.id,
            bodyID: bodyID,
            in: &model,
            tolerance: context.tolerance
        )
        try ExactFacePcurveBuilder().populateMissingPcurves(
            in: &model,
            tolerance: context.tolerance
        )
        do {
            try model.validate(level: .volumetric, tolerance: context.tolerance)
        } catch {
            throw KernelError.wrapping(
                error,
                phase: .topology,
                featureID: feature.id,
                tolerance: context.tolerance
            )
        }
        let identity = try identityBuilder.identity(
            featureID: feature.id,
            bodyID: bodyID,
            model: model,
            context: context
        )
        return EvaluationResult(
            brep: model,
            subshapes: identity.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: identity.lineage
        )
    }

    private func resolvedAngle(
        _ expression: CADExpression,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(
            expression,
            parameters: context.parameters,
            variables: [:]
        )
        guard quantity.kind == .angle else {
            throw kernelError(
                .invalidInput,
                featureID: featureID,
                tolerance: context.tolerance,
                "Face draft angle must resolve to an angle quantity."
            )
        }
        guard quantity.value.isFinite,
              abs(quantity.value) > context.tolerance.angle else {
            throw kernelError(
                .invalidInput,
                featureID: featureID,
                residual: quantity.value,
                tolerance: context.tolerance,
                "Face draft angle must be finite and larger than angular tolerance."
            )
        }
        let maximum = Double.pi / 2.0 - context.tolerance.angle
        guard abs(quantity.value) < maximum else {
            throw kernelError(
                .unsupportedCapability,
                featureID: featureID,
                residual: quantity.value,
                tolerance: context.tolerance,
                "Face draft angle magnitude must be smaller than 90 degrees."
            )
        }
        return quantity.value
    }

    private func targetFaceID(
        for stableReference: StableSubshapeReference,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> FaceID {
        let reference = try subshapeResolver.topologyReference(
            for: stableReference,
            model: context.brep,
            subshapes: context.subshapes,
            lineage: context.lineage,
            tolerance: context.tolerance
        )
        guard case let .face(faceID) = reference else {
            throw kernelError(
                .missingReference,
                featureID: featureID,
                subshapeID: stableReference.subshapeID,
                tolerance: context.tolerance,
                "Face draft selection did not resolve to a face."
            )
        }
        return faceID
    }

    private func draftFaces(
        _ targetFaceSubshapeIDs: [FaceID: SubshapeID],
        neutralFaceID: FaceID,
        angle: Double,
        bodyID: BodyID,
        featureID: FeatureID,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        guard let body = model.bodies[bodyID], body.kind == .solid else {
            throw kernelError(
                .unsupportedCapability,
                featureID: featureID,
                tolerance: tolerance,
                "Face draft requires a solid target body."
            )
        }
        let bodyFaceIDs = try collectFaceIDs(in: body, model: model)
        guard Set(targetFaceSubshapeIDs.keys).isSubset(of: bodyFaceIDs),
              bodyFaceIDs.contains(neutralFaceID) else {
            throw kernelError(
                .missingReference,
                featureID: featureID,
                tolerance: tolerance,
                "Face draft target and neutral faces must belong to the target body."
            )
        }
        try validateLineOnly(body: body, model: model, featureID: featureID, tolerance: tolerance)
        let (_, neutralPlane) = try planarFace(
            neutralFaceID,
            featureID: featureID,
            subshapeID: nil,
            model: model,
            tolerance: tolerance
        )
        let neutralNormal = try neutralPlane.normal.normalized(tolerance: tolerance.distance)
        let neutralEdgeIDs = try edgeIDs(on: neutralFaceID, model: model)
        let tangent = tan(angle)
        var constraints: [VertexID: [PlanarDraftConstraint]] = [:]

        for faceID in targetFaceSubshapeIDs.keys.sorted() {
            let subshapeID = targetFaceSubshapeIDs[faceID]
            let (face, targetPlane) = try planarFace(
                faceID,
                featureID: featureID,
                subshapeID: subshapeID,
                model: model,
                tolerance: tolerance
            )
            let targetEdgeIDs = try edgeIDs(on: faceID, model: model)
            let sharedEdgeIDs = targetEdgeIDs.intersection(neutralEdgeIDs).sorted()
            guard sharedEdgeIDs.count == 1,
                  let sharedEdgeID = sharedEdgeIDs.first,
                  let sharedEdge = model.edges[sharedEdgeID] else {
                throw kernelError(
                    .unsupportedCapability,
                    featureID: featureID,
                    subshapeID: subshapeID,
                    tolerance: tolerance,
                    "Each face draft target must share exactly one topological edge with the neutral face."
                )
            }
            let sharedVertexIDs: Set<VertexID> = [
                sharedEdge.startVertexID,
                sharedEdge.endVertexID,
            ]
            let outwardNormal = face.orientation == .forward
                ? targetPlane.normal
                : -targetPlane.normal
            let projectedNormal = outwardNormal - neutralNormal * outwardNormal.dot(neutralNormal)
            guard projectedNormal.length > max(tolerance.distance, tolerance.angle) else {
                throw kernelError(
                    .unsupportedCapability,
                    featureID: featureID,
                    subshapeID: subshapeID,
                    tolerance: tolerance,
                    "Face draft target normal must have a stable component in the neutral plane."
                )
            }
            let draftDirection = try projectedNormal.normalized(tolerance: tolerance.distance)
            let targetVertexIDs = try vertexIDs(on: faceID, model: model)
            var neutralVertexIDs = Set<VertexID>()
            var movedVertexCount = 0
            for vertexID in targetVertexIDs.sorted() {
                guard let vertex = model.vertices[vertexID] else {
                    throw TopologyError.missingReference("Face draft vertex is missing.")
                }
                let signedDistance = (vertex.point - neutralPlane.origin).dot(neutralNormal)
                if abs(signedDistance) <= tolerance.distance {
                    neutralVertexIDs.insert(vertexID)
                    continue
                }
                constraints[vertexID, default: []].append(PlanarDraftConstraint(
                    direction: draftDirection,
                    value: abs(signedDistance) * tangent
                ))
                movedVertexCount += 1
            }
            guard neutralVertexIDs == sharedVertexIDs,
                  movedVertexCount >= 1 else {
                throw kernelError(
                    .unsupportedCapability,
                    featureID: featureID,
                    subshapeID: subshapeID,
                    tolerance: tolerance,
                    "Face draft target must meet the neutral plane only at its shared edge."
                )
            }
        }

        let displacements = try constraintSolver.displacements(
            for: constraints,
            neutralNormal: neutralNormal,
            featureID: featureID,
            tolerance: tolerance
        )
        guard displacements.isEmpty == false else {
            throw kernelError(
                .unsupportedCapability,
                featureID: featureID,
                tolerance: tolerance,
                "Face draft did not resolve any movable vertices."
            )
        }
        for vertexID in displacements.keys.sorted() {
            guard var vertex = model.vertices[vertexID],
                  let displacement = displacements[vertexID] else {
                throw TopologyError.missingReference("Face draft displacement vertex is missing.")
            }
            vertex.point = vertex.point + displacement
            try vertex.point.validate()
            model.vertices[vertexID] = vertex
        }
    }

    private func validateLineOnly(
        body: Body,
        model: BRepModel,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws {
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Face draft shell is missing.")
            }
            for faceID in shell.faceIDs {
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Face draft face is missing.")
                }
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else {
                        throw TopologyError.missingReference("Face draft loop is missing.")
                    }
                    for coedge in loop.coedges {
                        guard let edge = model.edges[coedge.edgeID],
                              case .line = model.geometry.curves[edge.curveID] else {
                            throw kernelError(
                                .unsupportedCapability,
                                featureID: featureID,
                                tolerance: tolerance,
                                "Face draft requires line-only body topology."
                            )
                        }
                    }
                }
            }
        }
    }

    private func collectFaceIDs(in body: Body, model: BRepModel) throws -> Set<FaceID> {
        var result = Set<FaceID>()
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Face draft shell is missing.")
            }
            result.formUnion(shell.faceIDs)
        }
        return result
    }

    private func planarFace(
        _ faceID: FaceID,
        featureID: FeatureID,
        subshapeID: SubshapeID?,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> (Face, Plane3D) {
        guard let face = model.faces[faceID],
              case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else {
            throw kernelError(
                .unsupportedCapability,
                featureID: featureID,
                subshapeID: subshapeID,
                tolerance: tolerance,
                "Face draft requires planar target and neutral faces."
            )
        }
        return (face, plane)
    }

    private func edgeIDs(on faceID: FaceID, model: BRepModel) throws -> Set<EdgeID> {
        guard let face = model.faces[faceID] else {
            throw TopologyError.missingReference("Face draft face is missing.")
        }
        var result = Set<EdgeID>()
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                throw TopologyError.missingReference("Face draft loop is missing.")
            }
            result.formUnion(loop.coedges.map(\.edgeID))
        }
        return result
    }

    private func vertexIDs(on faceID: FaceID, model: BRepModel) throws -> Set<VertexID> {
        guard let face = model.faces[faceID] else {
            throw TopologyError.missingReference("Face draft face is missing.")
        }
        var result = Set<VertexID>()
        for loopID in face.loops {
            result.formUnion(try model.orderedVertexIDs(for: loopID))
        }
        return result
    }

    private func kernelError(
        _ code: KernelErrorCode,
        featureID: FeatureID,
        subshapeID: SubshapeID? = nil,
        residual: Double? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .evaluation,
            code: code,
            featureID: featureID,
            subshapeID: subshapeID,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
