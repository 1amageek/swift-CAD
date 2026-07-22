import CADCore
import CADIR
import CADTopology

package struct SubshapeGeometrySignatureBuilder {
    package let model: BRepModel
    package let tolerance: ModelingTolerance

    package init(model: BRepModel, tolerance: ModelingTolerance) {
        self.model = model
        self.tolerance = tolerance
    }

    package func signature(
        for reference: TopologyReference
    ) throws -> SubshapeGeometrySignature {
        try tolerance.validate()
        switch reference {
        case let .body(bodyID):
            return .body(try bodySignature(bodyID))
        case let .vertex(vertexID):
            guard let vertex = model.vertices[vertexID] else {
                throw missingTopology("vertex")
            }
            return .vertex(point: vertex.point)
        case let .edge(edgeID):
            return .edge(try edgeSignature(edgeID))
        case let .face(faceID):
            return .face(try faceSignature(faceID))
        }
    }

    package func matches(
        _ lhs: SubshapeGeometrySignature,
        _ rhs: SubshapeGeometrySignature
    ) -> Bool {
        switch (lhs, rhs) {
        case let (.body(first), .body(second)):
            return first == second
        case let (.face(first), .face(second)):
            return first == second
        case let (.vertex(first), .vertex(second)):
            return first.isApproximatelyEqual(to: second, tolerance: tolerance.distance)
        case let (.edge(first), .edge(second)):
            return first == second
        default:
            return false
        }
    }

    private func bodySignature(_ bodyID: BodyID) throws -> BodyGeometrySignature {
        guard let body = model.bodies[bodyID] else {
            throw missingTopology("body")
        }
        let shells = try body.shellIDs.map { shellID -> ShellGeometrySignature in
            guard let shell = model.shells[shellID] else {
                throw missingTopology("shell")
            }
            return ShellGeometrySignature(
                orientation: shell.orientation,
                faces: try shell.faceIDs.map(faceSignature)
            )
        }
        return BodyGeometrySignature(kind: body.kind, shells: shells)
    }

    private func faceSignature(_ faceID: FaceID) throws -> FaceGeometrySignature {
        guard let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID] else {
            throw missingTopology("face")
        }
        let loops = try face.loops.map { loopID -> LoopGeometrySignature in
            guard let loop = model.loops[loopID] else {
                throw missingTopology("loop")
            }
            return LoopGeometrySignature(
                role: loop.role,
                coedges: try loop.coedges.map { coedge in
                    guard let parameterCurve = coedge.surfaceParameterCurve else {
                        throw KernelError(
                            phase: .topology,
                            code: .topologyFailure,
                            tolerance: tolerance,
                            message: "Stable face geometry requires every coedge to carry a pcurve."
                        )
                    }
                    return CoedgeGeometrySignature(
                        edge: try edgeSignature(coedge.edgeID),
                        orientation: coedge.orientation,
                        surfaceParameterCurve: parameterCurve
                    )
                }
            )
        }
        return FaceGeometrySignature(
            surface: surface,
            orientation: face.orientation,
            loops: loops
        )
    }

    private func edgeSignature(_ edgeID: EdgeID) throws -> CurveSpanGeometrySignature {
        guard let edge = model.edges[edgeID],
              let curve = model.geometry.curves[edge.curveID],
              let start = model.vertices[edge.startVertexID]?.point,
              let end = model.vertices[edge.endVertexID]?.point else {
            throw missingTopology("edge")
        }
        return CurveSpanGeometrySignature(
            curve: curve,
            startParameter: edge.trim?.startParameter,
            endParameter: edge.trim?.endParameter,
            startPoint: start,
            endPoint: end
        )
    }

    private func missingTopology(_ kind: String) -> KernelError {
        KernelError(
            phase: .evaluation,
            code: .missingReference,
            tolerance: tolerance,
            message: "Stable selection geometry signature references a missing \(kind)."
        )
    }
}
