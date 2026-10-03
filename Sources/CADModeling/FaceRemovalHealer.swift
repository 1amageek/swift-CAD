import Foundation
import CADCore
import CADGeometry
import CADTopology

/// Heals a solid over faces taken out of it: each removed face collapses onto the faces around
/// it, which keep their surfaces, and the edges and vertices where they now meet are re-solved
/// from those surfaces (`BRepSurfaceMeetingSolver`).
///
/// A face a hole runs through leaves each face around it without that hole's loop. A strip
/// between two faces (a fillet or a chamfer) collapses onto their meeting: its two edges with them
/// become one edge on their intersection, and each of its other edges shrinks to a point. A face
/// collapses to the point where the faces around it meet. Topology identities are kept where
/// they survive: the merged edge keeps the first strip edge's identity, and merged vertices the
/// least one's.
package struct FaceRemovalHealer: Sendable {
    /// How a removed face collapses.
    package enum Collapse: Hashable, Sendable {
        /// Every loop the face leaves in a face around it is a whole inner loop, which goes.
        case dropsHoles
        /// The face is a strip between the faces across `first` and `second`, which meet where it
        /// was.
        case toEdge(first: EdgeID, second: EdgeID)
        /// The faces around it meet at one point where it was.
        case toPoint
    }

    package init() {}

    package func heal(
        _ plan: [FaceID: Collapse],
        bodyID: BodyID,
        featureID: FeatureID,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard plan.isEmpty == false else {
            throw failure(.invalidInput, featureID, tolerance, "Healing removes at least one face.")
        }
        guard let body = model.bodies[bodyID] else {
            throw failure(.missingReference, featureID, tolerance, "The healed body is missing.")
        }
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        let bodyFaces = scope.references.compactMap { reference -> FaceID? in
            guard case let .face(id) = reference else { return nil }
            return id
        }.sorted()
        let removed = Set(plan.keys)
        guard removed.isSubset(of: Set(bodyFaces)) else {
            throw failure(.missingReference, featureID, tolerance, "A removed face does not belong to the healed body.")
        }
        guard removed.count < bodyFaces.count else {
            throw failure(.invalidInput, featureID, tolerance, "Healing must keep at least one face.")
        }
        var facesOfEdge: [EdgeID: [FaceID]] = [:]
        var loopOfEdgeInFace: [FaceID: [EdgeID: LoopID]] = [:]
        for faceID in bodyFaces {
            for loopID in model.faces[faceID]?.loops ?? [] {
                guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("A healed body's loop is missing.") }
                for coedge in loop.coedges {
                    facesOfEdge[coedge.edgeID, default: []].append(faceID)
                    loopOfEdgeInFace[faceID, default: [:]][coedge.edgeID] = loopID
                }
            }
        }
        func edges(of faceID: FaceID) throws -> [EdgeID] {
            guard let face = model.faces[faceID] else { throw TopologyError.missingReference("A removed face is missing.") }
            return try face.loops.flatMap { loopID -> [EdgeID] in
                guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("A removed face's loop is missing.") }
                return loop.coedges.map(\.edgeID)
            }
        }
        func edge(_ id: EdgeID) throws -> Edge {
            guard let edge = model.edges[id] else { throw TopologyError.missingReference("A healed body's edge is missing.") }
            return edge
        }

        // Vertices that come together, as classes under the least vertex of each.
        var parent: [VertexID: VertexID] = [:]
        func find(_ vertex: VertexID) -> VertexID {
            var root = vertex
            while let next = parent[root], next != root { root = next }
            return root
        }
        func union(_ a: VertexID, _ b: VertexID) {
            let (ra, rb) = (find(a), find(b))
            guard ra != rb else { return }
            if ra < rb { parent[rb] = ra } else { parent[ra] = rb }
        }
        var vanishing = Set<EdgeID>()
        var merged: [EdgeID: EdgeID] = [:]
        var droppedLoops = Set<LoopID>()
        // The faces a hole runs through go together: each loop they leave in a kept face must be
        // a whole inner loop of their edges.
        var holeEdges = Set<EdgeID>()
        for (faceID, collapse) in plan where collapse == .dropsHoles { holeEdges.formUnion(try edges(of: faceID)) }
        for (faceID, collapse) in plan.sorted(by: { $0.key < $1.key }) {
            let faceEdges = try edges(of: faceID)
            switch collapse {
            case .dropsHoles:
                for edgeID in faceEdges {
                    vanishing.insert(edgeID)
                    let kept = (facesOfEdge[edgeID] ?? []).filter { removed.contains($0) == false }
                    guard let neighbour = kept.first else {
                        guard (facesOfEdge[edgeID] ?? []).allSatisfy({ plan[$0] == .dropsHoles }) else {
                            throw failure(.unsupportedCapability, featureID, tolerance,
                                          "A face a hole runs through meets a removed face that does not go with the hole.")
                        }
                        continue
                    }
                    guard kept.count == 1, let loopID = loopOfEdgeInFace[neighbour]?[edgeID], model.faces[neighbour]?.loops.first != loopID,
                          let loop = model.loops[loopID], loop.coedges.allSatisfy({ holeEdges.contains($0.edgeID) }) else {
                        throw failure(.unsupportedCapability, featureID, tolerance,
                                      "A removed face does not leave whole holes in the faces around it.")
                    }
                    droppedLoops.insert(loopID)
                }
            case .toPoint:
                for edgeID in faceEdges {
                    let edge = try edge(edgeID)
                    union(edge.startVertexID, edge.endVertexID)
                    vanishing.insert(edgeID)
                }
            case let .toEdge(first, second):
                guard first != second, faceEdges.contains(first), faceEdges.contains(second),
                      let firstSide = facesOfEdge[first]?.first(where: { $0 != faceID }),
                      let secondSide = facesOfEdge[second]?.first(where: { $0 != faceID }),
                      removed.contains(firstSide) == false, removed.contains(secondSide) == false, firstSide != secondSide else {
                    throw failure(.invalidInput, featureID, tolerance,
                                  "A collapsing strip's two edges must meet two different faces kept around it.")
                }
                for edgeID in faceEdges where edgeID != first && edgeID != second {
                    let edge = try edge(edgeID)
                    union(edge.startVertexID, edge.endVertexID)
                    vanishing.insert(edgeID)
                }
                merged[second] = first
                vanishing.insert(second)
            }
        }
        // Each merged edge pair must run between the same two vertex classes.
        var sameSense: [EdgeID: Bool] = [:]
        for (second, first) in merged {
            let a = try edge(first)
            let b = try edge(second)
            let (a0, a1, b0, b1) = (find(a.startVertexID), find(a.endVertexID), find(b.startVertexID), find(b.endVertexID))
            guard Set([a0, a1]) == Set([b0, b1]) else {
                throw failure(.topologyFailure, featureID, tolerance, "A strip's two edges do not come together end to end.")
            }
            if a0 == a1 {
                let solver = BRepSurfaceMeetingSolver(tolerance: tolerance)
                sameSense[second] = try direction(of: first, model: model, solver: solver).dot(direction(of: second, model: model, solver: solver)) > 0
            } else {
                sameSense[second] = a0 == b0
            }
        }

        // The seed of each merged vertex: the middle of the vertices it gathers.
        var members: [VertexID: [VertexID]] = [:]
        for vertexID in parent.keys.sorted() { members[find(vertexID), default: []].append(vertexID) }
        var seeds: [VertexID: Point3D] = [:]
        for (root, gathered) in members {
            let all = Set(gathered + [root])
            let points = try all.map { id -> Point3D in
                guard let point = model.vertices[id]?.point else { throw TopologyError.missingReference("A healed body's vertex is missing.") }
                return point
            }
            seeds[root] = .origin + points.reduce(Vector3D.zero) { $0 + ($1 - .origin) } / Double(points.count)
        }
        // Where each merged edge now runs: between its two faces around, seeded by the strip's
        // two edges' middles.
        let solver = BRepSurfaceMeetingSolver(tolerance: tolerance)
        var oldDirections: [EdgeID: Vector3D] = [:]
        for (edgeID, _) in facesOfEdge where vanishing.contains(edgeID) == false {
            oldDirections[edgeID] = try direction(of: edgeID, model: model, solver: solver)
        }
        var mergedMiddles: [EdgeID: Point3D] = [:]
        for (second, first) in merged {
            let a = try middle(of: first, model: model, solver: solver)
            let b = try middle(of: second, model: model, solver: solver)
            mergedMiddles[first] = a + (b - a) * 0.5
        }

        // Topology: the removed faces and vanishing edges go, loops drop holes and take merged
        // edges, and edges run between vertex classes.
        for faceID in bodyFaces where removed.contains(faceID) == false {
            guard var face = model.faces[faceID] else { throw TopologyError.missingReference("A healed body's face is missing.") }
            var loops: [LoopID] = []
            for loopID in face.loops {
                if droppedLoops.contains(loopID) {
                    model.loops.removeValue(forKey: loopID)
                    continue
                }
                guard var loop = model.loops[loopID] else { throw TopologyError.missingReference("A healed body's loop is missing.") }
                loop.coedges = loop.coedges.compactMap { coedge in
                    if let first = merged[coedge.edgeID] {
                        let keeps = sameSense[coedge.edgeID] ?? true
                        let flipped: Orientation = coedge.orientation == .forward ? .reversed : .forward
                        return Coedge(edgeID: first, orientation: keeps ? coedge.orientation : flipped, surfaceParameterCurve: nil)
                    }
                    return vanishing.contains(coedge.edgeID) ? nil : coedge
                }
                guard loop.coedges.isEmpty == false else {
                    throw failure(.topologyFailure, featureID, tolerance, "A face around the removed faces would lose a whole loop.")
                }
                model.loops[loopID] = loop
                loops.append(loopID)
            }
            face.loops = loops
            model.faces[faceID] = face
        }
        for faceID in removed {
            for loopID in model.faces[faceID]?.loops ?? [] { model.loops.removeValue(forKey: loopID) }
            model.faces.removeValue(forKey: faceID)
        }
        for shellID in body.shellIDs {
            guard var shell = model.shells[shellID] else { throw TopologyError.missingReference("A healed body's shell is missing.") }
            shell.faceIDs.removeAll { removed.contains($0) }
            model.shells[shellID] = shell
        }
        var vanishingVertices = Set<VertexID>()
        for edgeID in vanishing {
            if let edge = model.edges.removeValue(forKey: edgeID) {
                vanishingVertices.insert(edge.startVertexID)
                vanishingVertices.insert(edge.endVertexID)
            }
        }
        var movedVertices = Set<VertexID>()
        for (edgeID, var edge) in model.edges where facesOfEdge[edgeID] != nil {
            let (start, end) = (find(edge.startVertexID), find(edge.endVertexID))
            if start != edge.startVertexID || end != edge.endVertexID {
                edge.startVertexID = start
                edge.endVertexID = end
                model.edges[edgeID] = edge
            }
        }
        for (root, gathered) in members {
            for vertexID in gathered where vertexID != root { model.vertices.removeValue(forKey: vertexID) }
            movedVertices.insert(root)
        }

        // Geometry: each merged edge on its faces' intersection, each gathered vertex where the
        // faces around it meet, and every edge reaching one run to it.
        var remainingFacesOfEdge: [EdgeID: [FaceID]] = [:]
        for faceID in bodyFaces where removed.contains(faceID) == false {
            for loopID in model.faces[faceID]?.loops ?? [] {
                for coedge in model.loops[loopID]?.coedges ?? [] { remainingFacesOfEdge[coedge.edgeID, default: []].append(faceID) }
            }
        }
        func surface(of faceID: FaceID) throws -> Surface3D {
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("A healed body's surface is missing.")
            }
            return surface
        }
        var ids = FeatureTopologyIDAllocator(featureID: featureID)
        var resolvedCurves: [EdgeID: Curve3D] = [:]
        for (first, seed) in mergedMiddles {
            guard let faces = remainingFacesOfEdge[first], faces.count == 2 else {
                throw failure(.topologyFailure, featureID, tolerance, "A collapsed strip's edge does not lie between two faces.")
            }
            let branch = try solver.nearestBranch(of: try surface(of: faces[0]), and: try surface(of: faces[1]), near: seed)
            guard let curve = branch.curve else {
                throw failure(.topologyFailure, featureID, tolerance, "The faces on either side of a collapsed strip do not meet.")
            }
            resolvedCurves[first] = curve
        }
        var edgesOfVertex: [VertexID: [EdgeID]] = [:]
        for (edgeID, edge) in model.edges where remainingFacesOfEdge[edgeID] != nil {
            edgesOfVertex[edge.startVertexID, default: []].append(edgeID)
            edgesOfVertex[edge.endVertexID, default: []].append(edgeID)
        }
        for vertexID in movedVertices.sorted() {
            guard let seed = seeds[vertexID] else { continue }
            var faces = Set<FaceID>()
            for edgeID in edgesOfVertex[vertexID] ?? [] { faces.formUnion(remainingFacesOfEdge[edgeID] ?? []) }
            var distinct: [Surface3D] = []
            for faceID in faces.sorted() {
                let candidate = try surface(of: faceID)
                if distinct.contains(candidate) == false { distinct.append(candidate) }
            }
            var point = try solver.crossingPoint(of: distinct, near: seed)
            if point == nil {
                for edgeID in (edgesOfVertex[vertexID] ?? []).sorted() {
                    guard let curve = resolvedCurves[edgeID] ?? model.edges[edgeID].flatMap({ model.geometry.curves[$0.curveID] }),
                          let edgeFaces = remainingFacesOfEdge[edgeID] else { continue }
                    let onCurve = try edgeFaces.map { try surface(of: $0) }
                    if let found = try solver.crossingPoint(on: curve, with: distinct.filter { onCurve.contains($0) == false }, near: seed) {
                        point = found
                        break
                    }
                }
            }
            guard let point else {
                throw failure(.topologyFailure, featureID, tolerance, "The faces around a removed face do not meet where it was.")
            }
            try point.validate()
            model.vertices[vertexID]?.point = point
        }
        var retrimmed = Set<EdgeID>()
        for (edgeID, var edge) in model.edges.sorted(by: { $0.key < $1.key }) where remainingFacesOfEdge[edgeID] != nil {
            let isMerged = resolvedCurves[edgeID] != nil
            guard isMerged || movedVertices.contains(edge.startVertexID) || movedVertices.contains(edge.endVertexID) else { continue }
            guard let start = model.vertices[edge.startVertexID]?.point, let end = model.vertices[edge.endVertexID]?.point,
                  let curve = resolvedCurves[edgeID] ?? model.geometry.curves[edge.curveID],
                  let sense = oldDirections[edgeID] else {
                throw TopologyError.missingReference("A healed body's edge geometry is missing.")
            }
            guard let trim = try solver.trim(curve, from: start, to: end, isClosed: edge.startVertexID == edge.endVertexID, sense: sense) else {
                throw failure(.topologyFailure, featureID, tolerance, "Healing over the removed faces collapses or reverses an edge.")
            }
            if isMerged {
                var curveID = ids.nextCurveID()
                while model.geometry.curves[curveID] != nil { curveID = ids.nextCurveID() }
                model.geometry.curves[curveID] = curve
                edge.curveID = curveID
            }
            edge.trim = trim
            model.edges[edgeID] = edge
            retrimmed.insert(edgeID)
        }
        for faceID in bodyFaces where removed.contains(faceID) == false {
            for loopID in model.faces[faceID]?.loops ?? [] {
                guard var loop = model.loops[loopID] else { continue }
                for index in loop.coedges.indices where retrimmed.contains(loop.coedges[index].edgeID) {
                    loop.coedges[index].surfaceParameterCurve = nil
                }
                model.loops[loopID] = loop
            }
        }
        // A vertex only vanished edges reached (a hole's) goes with them.
        let reachedVertices = Set(model.edges.values.flatMap { [$0.startVertexID, $0.endVertexID] })
        for vertexID in vanishingVertices where reachedVertices.contains(vertexID) == false {
            model.vertices.removeValue(forKey: vertexID)
        }
        let referencedCurves = Set(model.edges.values.map(\.curveID))
        model.geometry.curves = model.geometry.curves.filter { referencedCurves.contains($0.key) }
        let referencedSurfaces = Set(model.faces.values.map(\.surfaceID))
        model.geometry.surfaces = model.geometry.surfaces.filter { referencedSurfaces.contains($0.key) }
    }

    /// The direction an edge runs from its start.
    private func direction(of edgeID: EdgeID, model: BRepModel, solver: BRepSurfaceMeetingSolver) throws -> Vector3D {
        guard let edge = model.edges[edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
            throw TopologyError.missingReference("A healed body's edge geometry is missing.")
        }
        let tangent = try solver.tangent(of: curve, at: trim.startParameter)
        return trim.endParameter >= trim.startParameter ? tangent : tangent * -1
    }

    private func middle(of edgeID: EdgeID, model: BRepModel, solver: BRepSurfaceMeetingSolver) throws -> Point3D {
        guard let edge = model.edges[edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
            throw TopologyError.missingReference("A healed body's edge geometry is missing.")
        }
        return try curve.point(at: (trim.startParameter + trim.endParameter) / 2, tolerance: solver.tolerance)
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: code == .topologyFailure ? .topology : .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
