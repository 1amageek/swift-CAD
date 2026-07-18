import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct PlanarFaceTranslator: Sendable {
    package init() {}

    package func outwardNormal(
        faceID: FaceID,
        bodyID: BodyID,
        featureID: FeatureID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        let target = try planarFace(
            faceID: faceID,
            bodyID: bodyID,
            featureID: featureID,
            model: model,
            tolerance: tolerance
        )
        let reverseNormal = (target.shellOrientation == .reversed) != (target.face.orientation == .reversed)
        return reverseNormal ? -target.surfaceNormal : target.surfaceNormal
    }

    package func translate(
        faceID: FaceID,
        bodyID: BodyID,
        displacement: Vector3D,
        featureID: FeatureID,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        let target = try planarFace(
            faceID: faceID,
            bodyID: bodyID,
            featureID: featureID,
            model: model,
            tolerance: tolerance
        )
        try displacement.validate()
        guard displacement.length > tolerance.distance else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                message: "Direct face translation must be larger than modeling tolerance."
            )
        }
        var vertexIDs = Set<VertexID>()
        for loopID in target.face.loops {
            vertexIDs.formUnion(try model.orderedVertexIDs(for: loopID))
        }
        guard vertexIDs.count >= 3 else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                featureID: featureID,
                tolerance: tolerance,
                message: "Direct face edit target is degenerate."
            )
        }
        for vertexID in vertexIDs {
            guard var vertex = model.vertices[vertexID] else {
                throw TopologyError.missingReference("Direct face edit vertex is missing.")
            }
            vertex.point = vertex.point + displacement
            try vertex.point.validate()
            model.vertices[vertexID] = vertex
        }
    }

    private func planarFace(
        faceID: FaceID,
        bodyID: BodyID,
        featureID: FeatureID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> (face: Face, shellOrientation: Orientation, surfaceNormal: Vector3D) {
        guard let body = model.bodies[bodyID], body.kind == .solid else {
            throw unsupported(featureID: featureID, tolerance: tolerance, "Direct face editing requires one solid body.")
        }
        var owningShell: Shell?
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Direct face edit shell is missing.")
            }
            if shell.faceIDs.contains(faceID) {
                guard owningShell == nil else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        featureID: featureID,
                        tolerance: tolerance,
                        message: "Direct face edit target belongs to more than one shell."
                    )
                }
                owningShell = shell
            }
        }
        guard let owningShell,
              let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID],
              let surfaceNormal = planarNormal(from: surface) else {
            throw unsupported(featureID: featureID, tolerance: tolerance, "Direct face editing requires a planar face on the target body.")
        }
        return (face, owningShell.orientation, surfaceNormal)
    }

    private func planarNormal(from surface: Surface3D) -> Vector3D? {
        switch surface {
        case let .plane(plane):
            return plane.normal
        case let .analytic(.plane(_, normal)):
            return normal
        case .cylinder, .analytic, .bSpline:
            return nil
        }
    }

    private func unsupported(
        featureID: FeatureID,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: .validation,
            code: .unsupportedCapability,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }
}
