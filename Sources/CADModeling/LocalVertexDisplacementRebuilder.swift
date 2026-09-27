import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Moves vertices of one body and re-solves only the geometry around them, keeping every
/// topology identity.
///
/// Each edge ending at a moved vertex must be straight and becomes the line through its moved
/// ends. Each face bounded by such an edge must be planar; it becomes the plane through its moved
/// boundary when that boundary is still flat, and otherwise, when it is one loop of four straight
/// edges, the bilinear patch those four lines bound exactly. Every other face, edge and curve,
/// curved ones included, is left as it was, so a solid or a sheet with curved faces elsewhere
/// can be edited. A face whose outward side would turn over is refused.
package struct LocalVertexDisplacementRebuilder: Sendable {
    package init() {}

    package func displace(
        _ displacements: [VertexID: Vector3D],
        bodyID: BodyID,
        featureID: FeatureID,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard !displacements.isEmpty else {
            throw failure(.invalidInput, featureID, tolerance, "A direct edit moves at least one vertex.")
        }
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        for vertexID in displacements.keys where !scope.references.contains(.vertex(vertexID)) {
            throw failure(.missingReference, featureID, tolerance, "A moved vertex does not belong to the edited body.")
        }
        let faceIDs = scope.references.compactMap { reference -> FaceID? in
            guard case let .face(id) = reference else { return nil }
            return id
        }
        let edgeIDs = scope.references.compactMap { reference -> EdgeID? in
            guard case let .edge(id) = reference else { return nil }
            return id
        }

        let movedEdges = Set(try edgeIDs.filter { edgeID in
            guard let edge = model.edges[edgeID] else {
                throw TopologyError.missingReference("A direct edit edge is missing.")
            }
            return displacements[edge.startVertexID] != nil || displacements[edge.endVertexID] != nil
        })
        let affectedFaces = try faceIDs.filter { faceID in
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference("A direct edit face is missing.")
            }
            return try face.loops.contains { loopID in
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference("A direct edit loop is missing.")
                }
                return loop.coedges.contains { movedEdges.contains($0.edgeID) }
            }
        }.sorted()
        // The one displacement every moved vertex of a face receives, when they share one.
        func sharedDisplacement(of faceID: FaceID) throws -> (displacement: Vector3D, movesEveryVertex: Bool)? {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference("A direct edit face is missing.")
            }
            var moved: [Vector3D] = []
            var movesEveryVertex = true
            for loopID in face.loops {
                for vertexID in try model.orderedVertexIDs(for: loopID) {
                    if let displacement = displacements[vertexID] { moved.append(displacement) } else { movesEveryVertex = false }
                }
            }
            guard let first = moved.first,
                  moved.allSatisfy({ ($0 - first).length <= tolerance.distance }) else { return nil }
            return (first, movesEveryVertex)
        }
        var previousPlanes: [FaceID: Plane3D] = [:]
        var sweptFaces: Set<FaceID> = []
        for faceID in affectedFaces {
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("A direct edit face is missing.")
            }
            if let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance) {
                previousPlanes[faceID] = Plane3D(origin: plane.origin, normal: try plane.normal.normalized(tolerance: tolerance.distance))
                continue
            }
            // A cylinder whose moved vertices all slide along its axis keeps its surface: its
            // boundary only lengthens or shortens along the rulings.
            if case let .cylinder(cylinder) = surface, let shared = try sharedDisplacement(of: faceID),
               cylinder.axis.cross(shared.displacement).length <= tolerance.distance * max(1, cylinder.axis.length) {
                sweptFaces.insert(faceID)
                continue
            }
            throw failure(.unsupportedCapability, featureID, tolerance,
                          "A direct edit reshapes planar faces, and cylinders only along their axis, around the moved vertices.")
        }

        for (vertexID, displacement) in displacements {
            guard var vertex = model.vertices[vertexID] else {
                throw TopologyError.missingReference("A moved vertex is missing.")
            }
            try displacement.validate()
            vertex.point = vertex.point + displacement
            try vertex.point.validate()
            model.vertices[vertexID] = vertex
        }

        var ids = FeatureTopologyIDAllocator(featureID: featureID)
        for edgeID in movedEdges.sorted() {
            guard var edge = model.edges[edgeID],
                  let start = model.vertices[edge.startVertexID]?.point,
                  let end = model.vertices[edge.endVertexID]?.point else {
                throw TopologyError.missingReference("A direct edit edge is missing.")
            }
            let startDisplacement = displacements[edge.startVertexID] ?? .zero
            let endDisplacement = displacements[edge.endVertexID] ?? .zero
            let curveID = nextCurveID(&ids, model)
            switch model.geometry.curves[edge.curveID] {
            case .line:
                let delta = end - start
                // A straight edge keeps its sense: one that shrinks to nothing or turns over means
                // its ends passed each other.
                let previousDelta = delta - endDisplacement + startDisplacement
                guard delta.length > tolerance.distance, delta.dot(previousDelta) > 0 else {
                    throw failure(.topologyFailure, featureID, tolerance, "A direct edit collapsed or reversed an edge.")
                }
                model.geometry.curves[curveID] = .line(Line3D(origin: start, direction: try delta.normalized(tolerance: tolerance.distance)))
                edge.trim = CurveTrim(startParameter: 0, endParameter: delta.length)
            case let curve? where (startDisplacement - endDisplacement).length <= tolerance.distance
                && displacements[edge.startVertexID] != nil && displacements[edge.endVertexID] != nil:
                // A curved edge whose ends move together translates rigidly, keeping its parameters.
                model.geometry.curves[curveID] = try translated(curve, by: startDisplacement, featureID: featureID, tolerance: tolerance)
            default:
                throw failure(.unsupportedCapability, featureID, tolerance,
                              "A direct edit moves a curved edge only when both its ends move together.")
            }
            edge.curveID = curveID
            model.edges[edgeID] = edge
        }

        for faceID in sweptFaces {
            // The surface stays; its parameter curves follow the edges that moved.
            for loopID in model.faces[faceID]?.loops ?? [] { try clearPcurves(of: loopID, in: &model) }
        }
        for faceID in affectedFaces where !sweptFaces.contains(faceID) {
            guard var face = model.faces[faceID], let previousPlane = previousPlanes[faceID] else {
                throw TopologyError.missingReference("A direct edit face is missing.")
            }
            let previousNormal = previousPlane.normal
            let loopPoints = try face.loops.map { try model.orderedPoints(for: $0) }
            let outer = loopPoints[0]
            let plane: Plane3D
            if let shared = try sharedDisplacement(of: faceID), shared.movesEveryVertex {
                // The whole face translates, so it keeps its plane, moved.
                plane = Plane3D(origin: previousPlane.origin + shared.displacement, normal: previousNormal)
            } else {
                let normal = newellNormal(outer)
                guard normal.length > tolerance.distance * tolerance.distance else {
                    throw failure(.unsupportedCapability, featureID, tolerance,
                                  "A direct edit cannot re-solve a face its moved vertices do not span.")
                }
                let unitNormal = try normal.normalized(tolerance: tolerance.distance)
                guard unitNormal.dot(previousNormal) > 0 else {
                    throw failure(.topologyFailure, featureID, tolerance, "A direct edit would turn a face over.")
                }
                plane = Plane3D(origin: outer[0], normal: unitNormal)
            }
            let unitNormal = plane.normal
            var isFlat = loopPoints.joined().allSatisfy { abs(($0 - plane.origin).dot(unitNormal)) <= tolerance.distance }
            for loopID in face.loops where isFlat {
                isFlat = try curvedEdgesLie(onPlane: plane, loopID: loopID, movedEdges: movedEdges, model: model, tolerance: tolerance)
            }
            let surfaceID = nextSurfaceID(&ids, model)
            if isFlat {
                model.geometry.surfaces[surfaceID] = .plane(plane)
                face.surfaceID = surfaceID
                model.faces[faceID] = face
                for loopID in face.loops { try clearPcurves(of: loopID, in: &model) }
                continue
            }
            // A warped quad: the bilinear patch of its corners contains each of its four straight
            // edges as a boundary isoline, so the face keeps its topology exactly.
            guard face.loops.count == 1, let loopID = face.loops.first, var loop = model.loops[loopID],
                  loop.coedges.count == 4, outer.count == 4,
                  try loop.coedges.allSatisfy({ coedge in
                      guard let edge = model.edges[coedge.edgeID] else {
                          throw TopologyError.missingReference("A direct edit edge is missing.")
                      }
                      if case .line = model.geometry.curves[edge.curveID] { return true }
                      return false
                  }) else {
                throw failure(.unsupportedCapability, featureID, tolerance,
                              "A direct edit left a face that is neither flat nor a four-sided straight-edged patch.")
            }
            let patch = BSplineSurface3D(
                uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
                controlPoints: [[outer[0], outer[1]], [outer[3], outer[2]]]
            )
            try patch.validate(tolerance: tolerance)
            let center = try Surface3D.bSpline(patch).differentialGeometry(atU: 0.5, v: 0.5, tolerance: tolerance)
            guard center.tangentU.cross(center.tangentV).dot(previousNormal) > 0 else {
                throw failure(.topologyFailure, featureID, tolerance, "A direct edit would turn a face over.")
            }
            model.geometry.surfaces[surfaceID] = .bSpline(patch)
            face.surfaceID = surfaceID
            model.faces[faceID] = face
            // The loop runs corner 0 → 1 → 2 → 3, around the unit square counterclockwise.
            let pcurves: [SurfaceParameterCurve] = [
                .constantV(v: 0, uStart: 0, uEnd: 1),
                .constantU(u: 1, vStart: 0, vEnd: 1),
                .constantV(v: 1, uStart: 1, uEnd: 0),
                .constantU(u: 0, vStart: 1, vEnd: 0),
            ]
            for index in loop.coedges.indices { loop.coedges[index].surfaceParameterCurve = pcurves[index] }
            model.loops[loopID] = loop
        }
        let referencedCurves = Set(model.edges.values.map(\.curveID))
        model.geometry.curves = model.geometry.curves.filter { referencedCurves.contains($0.key) }
        let referencedSurfaces = Set(model.faces.values.map(\.surfaceID))
        model.geometry.surfaces = model.geometry.surfaces.filter { referencedSurfaces.contains($0.key) }
    }

    /// Whether the loop's curved edges, which do not move, still lie in `plane`.
    private func curvedEdgesLie(
        onPlane plane: Plane3D,
        loopID: LoopID,
        movedEdges: Set<EdgeID>,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard let loop = model.loops[loopID] else {
            throw TopologyError.missingReference("A direct edit loop is missing.")
        }
        func onPlane(_ point: Point3D) -> Bool { abs((point - plane.origin).dot(plane.normal)) <= tolerance.distance }
        for coedge in loop.coedges where !movedEdges.contains(coedge.edgeID) {
            guard let edge = model.edges[coedge.edgeID], let curve = model.geometry.curves[edge.curveID] else {
                throw TopologyError.missingReference("A direct edit edge is missing.")
            }
            switch curve {
            case .line:
                continue
            case let .circle(circle):
                let axis = try circle.normal.normalized(tolerance: tolerance.distance)
                guard onPlane(circle.center), abs(abs(axis.dot(plane.normal)) - 1) <= tolerance.angle else { return false }
            case let .bSpline(spline):
                guard spline.controlPoints.allSatisfy(onPlane) else { return false }
            default:
                return false
            }
        }
        return true
    }

    /// `curve` moved rigidly by `displacement`, with the same parameterization.
    private func translated(
        _ curve: Curve3D,
        by displacement: Vector3D,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> Curve3D {
        switch curve {
        case let .line(line):
            return .line(Line3D(origin: line.origin + displacement, direction: line.direction))
        case let .circle(circle):
            return .circle(Circle3D(center: circle.center + displacement, normal: circle.normal, radius: circle.radius))
        case var .bSpline(spline):
            spline.controlPoints = spline.controlPoints.map { $0 + displacement }
            return .bSpline(spline)
        default:
            throw failure(.unsupportedCapability, featureID, tolerance,
                          "A direct edit translates straight, circular and B-spline edges only.")
        }
    }

    private func clearPcurves(of loopID: LoopID, in model: inout BRepModel) throws {
        guard var loop = model.loops[loopID] else {
            throw TopologyError.missingReference("A direct edit loop is missing.")
        }
        for index in loop.coedges.indices { loop.coedges[index].surfaceParameterCurve = nil }
        model.loops[loopID] = loop
    }

    private func newellNormal(_ points: [Point3D]) -> Vector3D {
        var normal = Vector3D.zero
        for index in points.indices {
            let current = points[index], next = points[(index + 1) % points.count]
            normal = normal + Vector3D(
                x: (current.y - next.y) * (current.z + next.z),
                y: (current.z - next.z) * (current.x + next.x),
                z: (current.x - next.x) * (current.y + next.y)
            )
        }
        return normal
    }

    private func nextCurveID(_ ids: inout FeatureTopologyIDAllocator, _ model: BRepModel) -> CurveID {
        while true {
            let id = ids.nextCurveID()
            if model.geometry.curves[id] == nil { return id }
        }
    }

    private func nextSurfaceID(_ ids: inout FeatureTopologyIDAllocator, _ model: BRepModel) -> SurfaceID {
        while true {
            let id = ids.nextSurfaceID()
            if model.geometry.surfaces[id] == nil { return id }
        }
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: code == .topologyFailure ? .topology : .evaluation, code: code, featureID: featureID,
                    tolerance: tolerance, message: message)
    }
}
