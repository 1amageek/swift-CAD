import CADCore
import CADIR
import CADTopology

/// Moves a circular edge along its axis by translating the flat face it bounds, so the edge stays
/// the same circle and every face around it keeps its analytic surface.
///
/// The cap is the planar face the circle bounds whose normal is the circle's axis. Every edge and
/// vertex of the cap moves with it; the faces around the cap must contain the axis direction (a
/// coaxial cylinder or a plane parallel to the axis), so their surfaces stay as they are and only
/// the straight edges joining the cap to the rest of the body are rebuilt between their moved
/// ends. Anything else is an unsupported capability rather than an approximation.
package struct CircularEdgeCapTranslator {
    package init() {}

    package func translate(
        capBoundedBy edgeID: EdgeID,
        bodyID: BodyID,
        displacement: Vector3D,
        featureID: FeatureID,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        guard let edge = model.edges[edgeID], case let .circle(circle) = model.geometry.curves[edge.curveID] else {
            throw unsupported(featureID, tolerance, "Circular edge move requires a circular edge.")
        }
        guard displacement.cross(circle.normal).length <= tolerance.distance else {
            throw unsupported(featureID, tolerance, "A circular edge moves along its axis, so it stays the same circle.")
        }
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Circular edge move body is missing.")
        }
        let faceIDs = try body.shellIDs.flatMap { shellID -> [FaceID] in
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Circular edge move shell is missing.")
            }
            return shell.faceIDs
        }
        func edges(of faceID: FaceID) throws -> Set<EdgeID> {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference("Circular edge move face is missing.")
            }
            return try face.loops.reduce(into: Set<EdgeID>()) { result, loopID in
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference("Circular edge move loop is missing.")
                }
                result.formUnion(loop.coedges.map(\.edgeID))
            }
        }

        // The flat face the circle bounds, facing along its axis.
        var capFaceID: FaceID?
        for faceID in faceIDs where try edges(of: faceID).contains(edgeID) {
            guard let face = model.faces[faceID],
                  case let .plane(plane) = model.geometry.surfaces[face.surfaceID],
                  plane.normal.cross(circle.normal).length <= tolerance.angle else { continue }
            capFaceID = faceID
        }
        guard let capFaceID, let capFace = model.faces[capFaceID],
              case let .plane(capPlane) = model.geometry.surfaces[capFace.surfaceID] else {
            throw unsupported(featureID, tolerance, "A circular edge moves with the flat face it bounds; this edge bounds none.")
        }
        let capEdgeIDs = try edges(of: capFaceID)
        var capVertexIDs = Set<VertexID>()
        for id in capEdgeIDs {
            guard let capEdge = model.edges[id] else { throw TopologyError.missingReference("Circular edge move edge is missing.") }
            capVertexIDs.formUnion([capEdge.startVertexID, capEdge.endVertexID])
        }

        // Every face around the cap must contain the motion, so its surface stays as it is.
        var neighbourFaceIDs = Set<FaceID>()
        for faceID in faceIDs where faceID != capFaceID {
            let faceEdges = try edges(of: faceID)
            let touchesCap = try !faceEdges.isDisjoint(with: capEdgeIDs) || faceEdges.contains { id in
                guard let faceEdge = model.edges[id] else { throw TopologyError.missingReference("Circular edge move edge is missing.") }
                return capVertexIDs.contains(faceEdge.startVertexID) || capVertexIDs.contains(faceEdge.endVertexID)
            }
            guard touchesCap, let face = model.faces[faceID] else { continue }
            let containsMotion: Bool
            switch model.geometry.surfaces[face.surfaceID] {
            case let .plane(plane):
                containsMotion = abs(plane.normal.dot(displacement)) <= tolerance.distance
            case let .cylinder(cylinder):
                containsMotion = cylinder.axis.cross(displacement).length <= tolerance.distance
            default:
                containsMotion = false
            }
            guard containsMotion else {
                throw unsupported(featureID, tolerance, "A face around the circular edge would change shape if the edge moved; only coaxial cylinders and planes along the axis follow it.")
            }
            neighbourFaceIDs.insert(faceID)
        }

        var topologyIDs = FeatureTopologyIDAllocator(featureID: featureID)
        for vertexID in capVertexIDs {
            guard var vertex = model.vertices[vertexID] else { throw TopologyError.missingReference("Circular edge move vertex is missing.") }
            vertex.point = vertex.point + displacement
            try vertex.point.validate()
            model.vertices[vertexID] = vertex
        }
        let capSurfaceID = nextSurfaceID(model: model, topologyIDs: &topologyIDs)
        model.geometry.surfaces[capSurfaceID] = .plane(Plane3D(origin: capPlane.origin + displacement, normal: capPlane.normal))
        model.faces[capFaceID]?.surfaceID = capSurfaceID

        var affectedEdgeIDs = capEdgeIDs
        for faceID in neighbourFaceIDs { affectedEdgeIDs.formUnion(try edges(of: faceID)) }
        for id in affectedEdgeIDs.sorted() {
            guard var affected = model.edges[id] else { throw TopologyError.missingReference("Circular edge move edge is missing.") }
            let movesStart = capVertexIDs.contains(affected.startVertexID)
            let movesEnd = capVertexIDs.contains(affected.endVertexID)
            guard movesStart || movesEnd else { continue }
            let curve: Curve3D
            switch (model.geometry.curves[affected.curveID], movesStart && movesEnd) {
            case let (.circle(moved)?, true):
                curve = .circle(Circle3D(center: moved.center + displacement, normal: moved.normal, radius: moved.radius))
            case let (.line(moved)?, true):
                curve = .line(Line3D(origin: moved.origin + displacement, direction: moved.direction))
            case (.line?, false):
                // A straight edge joining the cap to the rest of the body, rebuilt between its ends.
                guard let start = model.vertices[affected.startVertexID]?.point,
                      let end = model.vertices[affected.endVertexID]?.point else {
                    throw TopologyError.missingReference("Circular edge move vertex is missing.")
                }
                let delta = end - start
                let previousDelta = delta - (movesEnd ? displacement : displacement * -1)
                // The joining edge keeps its sense; one that shrinks to nothing or turns over means
                // the cap passed through the rest of the body.
                guard delta.length > tolerance.distance, delta.dot(previousDelta) > 0 else {
                    throw unsupported(featureID, tolerance, "The circular edge would move onto or through the rest of the body.")
                }
                curve = .line(Line3D(origin: start, direction: try delta.normalized(tolerance: tolerance.distance)))
                affected.trim = CurveTrim(startParameter: 0, endParameter: delta.length)
            default:
                throw unsupported(featureID, tolerance, "Circular edge move follows straight and circular edges only.")
            }
            let curveID = nextCurveID(model: model, topologyIDs: &topologyIDs)
            model.geometry.curves[curveID] = curve
            affected.curveID = curveID
            model.edges[id] = affected
        }

        // Parameter curves of the faces that changed are rebuilt by the caller.
        for faceID in neighbourFaceIDs.union([capFaceID]) {
            for loopID in model.faces[faceID]?.loops ?? [] {
                guard var loop = model.loops[loopID] else { continue }
                for index in loop.coedges.indices { loop.coedges[index].surfaceParameterCurve = nil }
                model.loops[loopID] = loop
            }
        }
        let referencedCurveIDs = Set(model.edges.values.map(\.curveID))
        model.geometry.curves = model.geometry.curves.filter { referencedCurveIDs.contains($0.key) }
        let referencedSurfaceIDs = Set(model.faces.values.map(\.surfaceID))
        model.geometry.surfaces = model.geometry.surfaces.filter { referencedSurfaceIDs.contains($0.key) }
    }

    private func nextCurveID(model: BRepModel, topologyIDs: inout FeatureTopologyIDAllocator) -> CurveID {
        while true {
            let id = topologyIDs.nextCurveID()
            if model.geometry.curves[id] == nil { return id }
        }
    }

    private func nextSurfaceID(model: BRepModel, topologyIDs: inout FeatureTopologyIDAllocator) -> SurfaceID {
        while true {
            let id = topologyIDs.nextSurfaceID()
            if model.geometry.surfaces[id] == nil { return id }
        }
    }

    private func unsupported(_ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance, message: message)
    }
}
