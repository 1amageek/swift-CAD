import Foundation
import CADCore
import CADGeometry
import CADTopology

/// Delete Redundant Topology on a solid or a sheet: faces lying on one surface, facing out the
/// same way, merge across the edges between them, and edges on one curve between the same faces
/// merge across the vertex between them. Faces on planes and on non-periodic B-spline surfaces
/// merge; faces on periodic surfaces keep their splits, which the kernel keeps to bound a full
/// turn. The shape does not change.
package struct RedundantTopologyRemover: Sendable {
    package init() {}

    /// Removes the redundant faces, edges and vertices of the body; false when there were none.
    package func remove(bodyID: BodyID, featureID: FeatureID, model: inout BRepModel, tolerance: ModelingTolerance) throws -> Bool {
        try tolerance.validate()
        guard let body = model.bodies[bodyID] else { throw TopologyError.missingReference("The body is missing.") }
        let mergedFaces = try mergeFaces(of: body, featureID: featureID, model: &model, tolerance: tolerance)
        let mergedEdges = try mergeEdges(bodyID: bodyID, featureID: featureID, model: &model, tolerance: tolerance)
        let referencedCurves = Set(model.edges.values.map(\.curveID))
        model.geometry.curves = model.geometry.curves.filter { referencedCurves.contains($0.key) }
        let referencedSurfaces = Set(model.faces.values.map(\.surfaceID))
        model.geometry.surfaces = model.geometry.surfaces.filter { referencedSurfaces.contains($0.key) }
        return mergedFaces || mergedEdges
    }

    // MARK: Faces

    private func mergeFaces(of body: Body, featureID: FeatureID, model: inout BRepModel, tolerance: ModelingTolerance) throws -> Bool {
        let scope = try BodyTopologyScope(bodyID: body.id, model: model)
        let faces = scope.references.compactMap { reference -> FaceID? in
            guard case let .face(id) = reference else { return nil }
            return id
        }.sorted()
        var facesOfEdge: [EdgeID: [FaceID]] = [:]
        for faceID in faces {
            for loopID in model.faces[faceID]?.loops ?? [] {
                for coedge in model.loops[loopID]?.coedges ?? [] { facesOfEdge[coedge.edgeID, default: []].append(faceID) }
            }
        }
        // Edges between two faces on one mergeable surface facing out the same way.
        var parent: [FaceID: FaceID] = [:]
        func find(_ face: FaceID) -> FaceID {
            var root = face
            while let next = parent[root], next != root { root = next }
            return root
        }
        var redundant = Set<EdgeID>()
        for (edgeID, pair) in facesOfEdge.sorted(by: { $0.key < $1.key }) where pair.count == 2 && pair[0] != pair[1] {
            guard try sameMergeableSurface(pair[0], pair[1], model: model, tolerance: tolerance) else { continue }
            redundant.insert(edgeID)
            let (a, b) = (find(pair[0]), find(pair[1]))
            if a != b { if a < b { parent[b] = a } else { parent[a] = b } }
        }
        guard redundant.isEmpty == false else { return false }
        var groups: [FaceID: [FaceID]] = [:]
        for faceID in faces { groups[find(faceID), default: []].append(faceID) }
        let solver = BRepSurfaceMeetingSolver(tolerance: tolerance)
        var changed = false
        for (root, members) in groups.sorted(by: { $0.key < $1.key }) where members.count > 1 {
            // The coedges left once the edges between the members go, chained into loops.
            var remaining: [Coedge] = []
            for faceID in members {
                for loopID in model.faces[faceID]?.loops ?? [] {
                    guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("A loop is missing.") }
                    remaining += loop.coedges.filter { redundant.contains($0.edgeID) == false }
                }
            }
            guard let chained = try chain(remaining, model: model), chained.isEmpty == false else { continue }
            guard var face = model.faces[root], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("A merged face is missing.")
            }
            // The outer loop is the one enclosing the largest area on the face's surface.
            let areas = try chained.map { try enclosedArea(of: $0, on: surface, model: model, solver: solver) }
            guard let outer = areas.indices.max(by: { areas[$0] < areas[$1] }) else { continue }
            var ordered = chained
            ordered.swapAt(0, outer)
            var ids = FeatureTopologyIDAllocator(featureID: featureID)
            var loopIDs: [LoopID] = []
            for (index, coedges) in ordered.enumerated() {
                var loopID = ids.nextLoopID()
                while model.loops[loopID] != nil { loopID = ids.nextLoopID() }
                model.loops[loopID] = Loop(id: loopID, role: index == 0 ? .outer : .inner, coedges: coedges)
                loopIDs.append(loopID)
            }
            for faceID in members {
                for loopID in model.faces[faceID]?.loops ?? [] { model.loops.removeValue(forKey: loopID) }
                if faceID != root { model.faces.removeValue(forKey: faceID) }
            }
            face.loops = loopIDs
            model.faces[root] = face
            for shellID in body.shellIDs {
                guard var shell = model.shells[shellID] else { throw TopologyError.missingReference("A shell is missing.") }
                shell.faceIDs.removeAll { members.contains($0) && $0 != root }
                model.shells[shellID] = shell
            }
            changed = true
        }
        guard changed else { return false }
        let used = Set(model.loops.values.flatMap { $0.coedges.map(\.edgeID) })
        for edgeID in redundant where used.contains(edgeID) == false {
            if let edge = model.edges.removeValue(forKey: edgeID) {
                for vertexID in [edge.startVertexID, edge.endVertexID]
                where model.edges.values.contains(where: { $0.startVertexID == vertexID || $0.endVertexID == vertexID }) == false {
                    model.vertices.removeValue(forKey: vertexID)
                }
            }
        }
        return true
    }

    /// Whether two faces lie on one surface facing out the same way, and it is a plane or a
    /// non-periodic B-spline surface.
    private func sameMergeableSurface(_ a: FaceID, _ b: FaceID, model: BRepModel, tolerance: ModelingTolerance) throws -> Bool {
        guard let first = model.faces[a], let second = model.faces[b],
              let firstSurface = model.geometry.surfaces[first.surfaceID], let secondSurface = model.geometry.surfaces[second.surfaceID] else {
            throw TopologyError.missingReference("A face is missing.")
        }
        let planes = DefaultPlanarSurfaceResolver()
        if let p = try planes.exactPlane(for: firstSurface, tolerance: tolerance), let q = try planes.exactPlane(for: secondSurface, tolerance: tolerance) {
            let n = try p.normal.normalized(tolerance: tolerance.distance)
            let m = try q.normal.normalized(tolerance: tolerance.distance)
            let outwardN = first.orientation == .forward ? n : n * -1
            let outwardM = second.orientation == .forward ? m : m * -1
            return outwardN.cross(outwardM).length <= tolerance.angle && outwardN.dot(outwardM) > 0
                && abs((q.origin - p.origin).dot(n)) <= tolerance.distance
        }
        guard first.surfaceID == second.surfaceID || firstSurface == secondSurface, first.orientation == second.orientation else { return false }
        if case let .bSpline(spline) = firstSurface {
            if case .periodic = spline.uDomain { return false }
            if case .periodic = spline.vDomain { return false }
            return true
        }
        return false
    }

    /// The coedges joined end to start into closed loops; nil when a vertex offers more than one
    /// way on, so the loops are not determined.
    private func chain(_ coedges: [Coedge], model: BRepModel) throws -> [[Coedge]]? {
        func ends(_ coedge: Coedge) throws -> (start: VertexID, end: VertexID) {
            guard let edge = model.edges[coedge.edgeID] else { throw TopologyError.missingReference("An edge is missing.") }
            return coedge.orientation == .forward ? (edge.startVertexID, edge.endVertexID) : (edge.endVertexID, edge.startVertexID)
        }
        var outgoing: [VertexID: [Int]] = [:]
        for (index, coedge) in coedges.enumerated() { outgoing[try ends(coedge).start, default: []].append(index) }
        guard outgoing.values.allSatisfy({ $0.count == 1 }) else { return nil }
        var used = Set<Int>()
        var loops: [[Coedge]] = []
        for start in coedges.indices where used.contains(start) == false {
            var loop: [Coedge] = []
            var index = start
            while used.insert(index).inserted {
                loop.append(coedges[index])
                guard let next = outgoing[try ends(coedges[index]).end]?.first else { return nil }
                index = next
            }
            guard index == start else { return nil }
            loops.append(loop)
        }
        return loops
    }

    /// The area a loop encloses on a surface, from its points' surface parameters.
    private func enclosedArea(of loop: [Coedge], on surface: Surface3D, model: BRepModel, solver: BRepSurfaceMeetingSolver) throws -> Double {
        var parameters: [(Double, Double)] = []
        for coedge in loop {
            guard let edge = model.edges[coedge.edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
                throw TopologyError.missingReference("An edge's geometry is missing.")
            }
            let (from, to) = coedge.orientation == .forward ? (trim.startParameter, trim.endParameter) : (trim.endParameter, trim.startParameter)
            for step in 0..<8 {
                let point = try curve.point(at: from + (to - from) * Double(step) / 8, tolerance: solver.tolerance)
                guard case let .projected(projection) = try surface.parameterProjectionResult(of: point, tolerance: solver.tolerance) else {
                    throw TopologyError.missingReference("A loop leaves its face's surface.")
                }
                parameters.append((projection.u, projection.v))
            }
        }
        let twice = parameters.indices.reduce(0.0) { sum, index in
            let (a, b) = (parameters[index], parameters[(index + 1) % parameters.count])
            return sum + a.0 * b.1 - b.0 * a.1
        }
        return abs(twice) / 2
    }

    // MARK: Edges

    private func mergeEdges(bodyID: BodyID, featureID: FeatureID, model: inout BRepModel, tolerance: ModelingTolerance) throws -> Bool {
        let solver = BRepSurfaceMeetingSolver(tolerance: tolerance)
        var changed = false
        // Vertices whose edges cannot run on through them, which stay.
        var kept = Set<VertexID>()
        while true {
            let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
            var facesOfEdge: [EdgeID: [FaceID]] = [:]
            var loopsOfEdge: [EdgeID: [LoopID]] = [:]
            for case let .face(faceID) in scope.references {
                for loopID in model.faces[faceID]?.loops ?? [] {
                    for coedge in model.loops[loopID]?.coedges ?? [] {
                        facesOfEdge[coedge.edgeID, default: []].append(faceID)
                        loopsOfEdge[coedge.edgeID, default: []].append(loopID)
                    }
                }
            }
            var edgesOfVertex: [VertexID: [EdgeID]] = [:]
            for edgeID in facesOfEdge.keys.sorted() {
                guard let edge = model.edges[edgeID] else { continue }
                edgesOfVertex[edge.startVertexID, default: []].append(edgeID)
                if edge.endVertexID != edge.startVertexID { edgesOfVertex[edge.endVertexID, default: []].append(edgeID) }
            }
            // A vertex between just two edges on one curve, bounding the same faces.
            var merge: (vertex: VertexID, kept: EdgeID, gone: EdgeID)?
            for (vertexID, edges) in edgesOfVertex.sorted(by: { $0.key < $1.key })
            where edges.count == 2 && edges[0] != edges[1] && kept.contains(vertexID) == false {
                let (a, b) = (edges[0], edges[1])
                guard Set(facesOfEdge[a] ?? []) == Set(facesOfEdge[b] ?? []), (facesOfEdge[a] ?? []).count == (facesOfEdge[b] ?? []).count,
                      let first = model.edges[a], let second = model.edges[b],
                      // Two edges closing one curve stay two, since a closed edge needs a vertex of its own.
                      Set([first.startVertexID, first.endVertexID, second.startVertexID, second.endVertexID]).count == 3,
                      try sameCarrier(a, b, model: model, tolerance: tolerance) else { continue }
                merge = (vertexID, min(a, b), max(a, b))
                break
            }
            guard let merge else { return changed }
            guard var runOn = model.edges[merge.kept], let gone = model.edges[merge.gone],
                  let curve = model.geometry.curves[runOn.curveID], let keptTrim = runOn.trim else {
                throw TopologyError.missingReference("A merged edge's geometry is missing.")
            }
            // The kept edge runs on through the vertex to the gone edge's far end.
            let far = gone.startVertexID == merge.vertex ? gone.endVertexID : gone.startVertexID
            let sense = try solver.tangent(of: curve, at: keptTrim.startParameter) * (keptTrim.endParameter >= keptTrim.startParameter ? 1 : -1)
            if runOn.startVertexID == merge.vertex {
                runOn.startVertexID = far
            } else {
                runOn.endVertexID = far
            }
            guard let start = model.vertices[runOn.startVertexID]?.point, let end = model.vertices[runOn.endVertexID]?.point,
                  let trim = try solver.trim(curve, from: start, to: end, isClosed: false, sense: sense) else {
                kept.insert(merge.vertex)
                continue
            }
            runOn.trim = trim
            model.edges[merge.kept] = runOn
            model.edges.removeValue(forKey: merge.gone)
            model.vertices.removeValue(forKey: merge.vertex)
            for loopID in loopsOfEdge[merge.gone] ?? [] {
                guard var loop = model.loops[loopID],
                      let keptIndex = loop.coedges.firstIndex(where: { $0.edgeID == merge.kept }),
                      let goneIndex = loop.coedges.firstIndex(where: { $0.edgeID == merge.gone }) else { continue }
                // The two parameter curves run on into one where they are isolines or polylines;
                // otherwise the merged edge's is rebuilt.
                let count = loop.coedges.count
                let (first, second) = (keptIndex + 1) % count == goneIndex
                    ? (loop.coedges[keptIndex].surfaceParameterCurve, loop.coedges[goneIndex].surfaceParameterCurve)
                    : (loop.coedges[goneIndex].surfaceParameterCurve, loop.coedges[keptIndex].surfaceParameterCurve)
                loop.coedges[keptIndex].surfaceParameterCurve = joined(first, second)
                loop.coedges.remove(at: goneIndex)
                model.loops[loopID] = loop
            }
            changed = true
        }
    }

    /// One parameter curve running through `first` and then `second`, when both are the same
    /// isoline or both polylines; nil otherwise.
    private func joined(_ first: SurfaceParameterCurve?, _ second: SurfaceParameterCurve?) -> SurfaceParameterCurve? {
        switch (first, second) {
        case let (.constantU(u1, start, _)?, .constantU(u2, _, end)?) where u1 == u2:
            return .constantU(u: u1, vStart: start, vEnd: end)
        case let (.constantV(v1, start, _)?, .constantV(v2, _, end)?) where v1 == v2:
            return .constantV(v: v1, uStart: start, uEnd: end)
        case let (.polyline(a)?, .polyline(b)?):
            return .polyline(a + b.dropFirst())
        default:
            return nil
        }
    }

    /// Whether two edges lie on one curve: one line, one circle, or the same curve.
    private func sameCarrier(_ a: EdgeID, _ b: EdgeID, model: BRepModel, tolerance: ModelingTolerance) throws -> Bool {
        guard let first = model.edges[a], let second = model.edges[b],
              let c1 = model.geometry.curves[first.curveID], let c2 = model.geometry.curves[second.curveID] else {
            throw TopologyError.missingReference("An edge is missing.")
        }
        if first.curveID == second.curveID || c1 == c2 { return true }
        let solver = BRepSurfaceMeetingSolver(tolerance: tolerance)
        // Each edge's ends lie on the other's curve, and at the shared vertex they run on.
        let ends = [first.startVertexID, first.endVertexID, second.startVertexID, second.endVertexID].compactMap { model.vertices[$0]?.point }
        switch (c1, c2) {
        case (.line, .line), (.analytic(.line), .analytic(.line)), (.line, .analytic(.line)), (.analytic(.line), .line):
            for point in ends where (try solver.closest(to: point, on: c1).point - point).length > tolerance.distance { return false }
            return true
        case (.circle(let p), .circle(let q)):
            return (p.center - q.center).length <= tolerance.distance && abs(p.radius - q.radius) <= tolerance.distance
                && p.normal.cross(q.normal).length <= tolerance.angle * max(p.normal.length, 1)
        default:
            return false
        }
    }
}
