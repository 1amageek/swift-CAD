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
    package func remove(bodyID: BodyID, featureID: FeatureID, model: inout BRepModel,
        tolerance: ModelingTolerance) throws -> Bool {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try remove(bodyID: bodyID, featureID: featureID, model: &model,
            tolerance: tolerance, using: &execution)
    }

    package func remove(bodyID: BodyID, featureID: FeatureID, model: inout BRepModel, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
        try tolerance.validate()
        guard let body = model.bodies[bodyID] else { throw TopologyError.missingReference("The body is missing.") }
        let mergedFaces = try mergeFaces(of: body, featureID: featureID, model: &model, tolerance: tolerance, using: &execution)
        let mergedEdges = try mergeEdges(bodyID: bodyID, featureID: featureID, model: &model, tolerance: tolerance, using: &execution)
        let referencedCurves = try OriginalParameterQueryStorage.set(try OriginalParameterQueryStorage.map(model.edges.values, using: &execution) { edge, execution in edge.curveID }, using: &execution)
        for key in try OriginalParameterQueryStorage.materialize(model.geometry.curves.keys, using: &execution) {
            try execution.consumeWork(1)
            if !referencedCurves.contains(key) {
                try execution.retainStorage(bytes: MemoryLayout<(CurveID, Curve3D)>.stride)
                model.geometry.curves.removeValue(forKey: key)
            }
        }
        let referencedSurfaces = try OriginalParameterQueryStorage.set(try OriginalParameterQueryStorage.map(model.faces.values, using: &execution) { face, execution in face.surfaceID }, using: &execution)
        for key in try OriginalParameterQueryStorage.materialize(model.geometry.surfaces.keys, using: &execution) {
            try execution.consumeWork(1)
            if !referencedSurfaces.contains(key) {
                try execution.retainStorage(bytes: MemoryLayout<(SurfaceID, Surface3D)>.stride)
                model.geometry.surfaces.removeValue(forKey: key)
            }
        }
        return mergedFaces || mergedEdges
    }

    // MARK: Faces

    private func mergeFaces(of body: Body, featureID: FeatureID, model: inout BRepModel, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
        let scope = try BodyTopologyScope(bodyID: body.id, model: model, using: &execution)
        let selectedFaces = try OriginalParameterQueryStorage.compactMap(scope.references, using: &execution) { reference, execution -> FaceID? in
            guard case let .face(id) = reference else { return nil }
            return id
        }
        let faces = try OriginalParameterQueryStorage.ordered(selectedFaces, using: &execution, less: <)
        var facesOfEdge: [EdgeID: [FaceID]] = [:]
        var usesOfEdge: [EdgeID: [Coedge]] = [:]
        for faceID in faces {
            try execution.consumeWork(1)
            for loopID in model.faces[faceID]?.loops ?? [] {
                try execution.consumeWork(1)
                for coedge in model.loops[loopID]?.coedges ?? [] {
                    try execution.consumeWork(1)
                    try append(faceID, for: coedge.edgeID, in: &facesOfEdge, using: &execution)
                    try append(coedge, for: coedge.edgeID, in: &usesOfEdge, using: &execution)
                }
            }
        }
        // Edges between two faces on one mergeable surface facing out the same way.
        var parent: [FaceID: FaceID] = [:]
        func find(_ face: FaceID, using execution: inout OriginalQueryExecution) throws -> FaceID {
            var root = face
            while let next = parent[root], next != root { try execution.consumeWork(1); root = next }
            return root
        }
        var redundant = Set<EdgeID>()
        for (edgeID, pair) in try OriginalParameterQueryStorage.ordered(facesOfEdge, using: &execution, less: { $0.key < $1.key }) where pair.count == 2 && pair[0] != pair[1] {
            try execution.consumeWork(1)
            guard try sameMergeableSurface(pair[0], pair[1], model: model, tolerance: tolerance, using: &execution) else { continue }
            // On a periodic surface the edge whose two sides lie a whole period apart closes the
            // turn: it stays, the merged face's seam.
            if try closesTurn(edgeID, uses: usesOfEdge[edgeID] ?? [], face: pair[0], model: model, tolerance: tolerance, using: &execution) { continue }
            try OriginalParameterQueryStorage.insert(edgeID, in: &redundant, using: &execution)
            let (a, b) = (try find(pair[0], using: &execution), try find(pair[1], using: &execution))
            if a != b { if a < b { try OriginalParameterQueryStorage.set(a, for: b, in: &parent, using: &execution) } else { try OriginalParameterQueryStorage.set(b, for: a, in: &parent, using: &execution) } }
        }
        guard redundant.isEmpty == false else { return false }
        var groups: [FaceID: [FaceID]] = [:]
        for faceID in faces { try append(faceID, for: try find(faceID, using: &execution), in: &groups, using: &execution) }
        let solver = BRepSurfaceMeetingSolver(tolerance: tolerance)
        var changed = false
        for (root, members) in try OriginalParameterQueryStorage.ordered(groups, using: &execution, less: { $0.key < $1.key }) where members.count > 1 {
            try execution.consumeWork(1)
            // On a periodic surface the members may wrap all the way round: one edge between them
            // stays as the merged face's seam, and every coedge's parameter curve is carried into
            // one continuous chart so the seam's two sides lie a period apart.
            var periodicChart: Double?
            if let rootFace = model.faces[root], let rootSurface = model.geometry.surfaces[rootFace.surfaceID],
               let period = try SurfaceParameterTopology(surface: rootSurface, using: &execution).uPeriod {
                periodicChart = period
                let innerUnsorted = try OriginalParameterQueryStorage.filter(redundant, using: &execution) { edge, execution in
                    try OriginalParameterQueryStorage.allSatisfy(facesOfEdge[edge] ?? [], using: &execution) { face, execution in
                        try OriginalParameterQueryStorage.contains(members, using: &execution) { value, execution in value == face }
                    }
                }
                let inner = try OriginalParameterQueryStorage.ordered(innerUnsorted, using: &execution, less: <)
                let span = try OriginalParameterQueryStorage.reduce(members, initial: 0.0, using: &execution) { sum, face, execution in sum + (try uExtent(of: face, model: model, using: &execution)) }
                if span >= period * (1 - 1e-9) {
                    let across = try OriginalParameterQueryStorage.filter(inner, using: &execution) { edge, execution in
                        try OriginalParameterQueryStorage.allSatisfy(usesOfEdge[edge] ?? [], using: &execution) { use, execution in
                            if case .constantU? = use.surfaceParameterCurve { return true } else { return false }
                        }
                    }
                    guard let seam = try OriginalParameterQueryStorage.first(across, using: &execution, predicate: { edge, execution in try OriginalParameterQueryStorage.contains(usesOfEdge[edge] ?? [], using: &execution) { use, execution in
                        if case let .constantU(u, _, _)? = use.surfaceParameterCurve { return abs(u.remainder(dividingBy: period)) <= 1e-9 }
                        return false
                    } }) ?? across.first else { continue }
                    try execution.consumeWork(1)
                    redundant.remove(seam)
                }
            }
            // The coedges left once the edges between the members go, chained into loops.
            var remaining: [Coedge] = []
            for faceID in members {
                try execution.consumeWork(1)
                for loopID in model.faces[faceID]?.loops ?? [] {
                    try execution.consumeWork(1)
                    guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("A loop is missing.") }
                    let kept = try OriginalParameterQueryStorage.filter(loop.coedges, using: &execution) { coedge, execution in !redundant.contains(coedge.edgeID) }
                    let carried = try OriginalParameterQueryStorage.optionalMap(periodicChart, using: &execution) { period, execution in try continuousInChart(kept, of: loop.coedges, period: period, using: &execution) } ?? kept
                    try OriginalParameterQueryStorage.append(contentsOf: carried, to: &remaining, using: &execution)
                }
            }
            let chainedLoops = periodicChart == nil ? try chain(remaining, model: model, using: &execution) : try chainByParameter(remaining, model: model, using: &execution)
            guard let chained = chainedLoops, chained.isEmpty == false else { continue }
            guard var face = model.faces[root], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("A merged face is missing.")
            }
            // The outer loop is the one enclosing the largest area on the face's surface.
            let areas = try OriginalParameterQueryStorage.map(chained, using: &execution) { loop, execution in try enclosedArea(of: loop, on: surface, model: model, solver: solver, using: &execution) }
            var outer: Int?
            for index in areas.indices {
                try execution.consumeWork(1)
                if outer == nil || areas[outer!] < areas[index] { outer = index }
            }
            guard let outer else { continue }
            var ordered = try OriginalParameterQueryStorage.materialize(chained, using: &execution)
            ordered.swapAt(0, outer)
            var ids = FeatureTopologyIDAllocator(featureID: featureID)
            var loopIDs: [LoopID] = []
            for (index, coedges) in ordered.enumerated() {
                try execution.consumeWork(1)
                var loopID = ids.nextLoopID()
                while model.loops[loopID] != nil { try execution.consumeWork(1); loopID = ids.nextLoopID() }
                try OriginalParameterQueryStorage.set(Loop(id: loopID, role: index == 0 ? .outer : .inner, coedges: coedges), for: loopID, in: &model.loops, using: &execution)
                try OriginalParameterQueryStorage.append(loopID, to: &loopIDs, using: &execution)
            }
            for faceID in members {
                try execution.consumeWork(1)
                for loopID in model.faces[faceID]?.loops ?? [] {
                    try execution.consumeWork(1)
                    try execution.retainStorage(bytes: MemoryLayout<(LoopID, Loop)>.stride)
                    model.loops.removeValue(forKey: loopID)
                }
                if faceID != root {
                    try execution.retainStorage(bytes: MemoryLayout<(FaceID, Face)>.stride)
                    model.faces.removeValue(forKey: faceID)
                }
            }
            face.loops = loopIDs
            try OriginalParameterQueryStorage.set(face, for: root, in: &model.faces, using: &execution)
            for shellID in body.shellIDs {
                try execution.consumeWork(1)
                guard var shell = model.shells[shellID] else { throw TopologyError.missingReference("A shell is missing.") }
                shell.faceIDs = try OriginalParameterQueryStorage.filter(shell.faceIDs, using: &execution) { face, execution in
                    let member = try OriginalParameterQueryStorage.contains(members, using: &execution) { value, execution in value == face }
                    return !member || face == root
                }
                try OriginalParameterQueryStorage.set(shell, for: shellID, in: &model.shells, using: &execution)
            }
            changed = true
        }
        guard changed else { return false }
        let used = try OriginalParameterQueryStorage.set(try OriginalParameterQueryStorage.flatMap(model.loops.values, using: &execution) { loop, execution in
            try OriginalParameterQueryStorage.map(loop.coedges, using: &execution) { coedge, execution in coedge.edgeID }
        }, using: &execution)
        for edgeID in redundant where used.contains(edgeID) == false {
            try execution.consumeWork(1)
            try execution.retainStorage(bytes: MemoryLayout<(EdgeID, Edge)>.stride)
            if let edge = model.edges.removeValue(forKey: edgeID) {
                for vertexID in [edge.startVertexID, edge.endVertexID]
                where try OriginalParameterQueryStorage.contains(model.edges.values, using: &execution, predicate: { edge, execution in edge.startVertexID == vertexID || edge.endVertexID == vertexID }) == false {
                    try execution.consumeWork(1)
                    try execution.retainStorage(bytes: MemoryLayout<(VertexID, Vertex)>.stride)
                    model.vertices.removeValue(forKey: vertexID)
                }
            }
        }
        return true
    }

    /// Whether two faces lie on one surface facing out the same way, and it is a plane or a
    /// non-periodic B-spline surface.
    private func sameMergeableSurface(_ a: FaceID, _ b: FaceID, model: BRepModel, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
        guard let first = model.faces[a], let second = model.faces[b],
              let firstSurface = model.geometry.surfaces[first.surfaceID], let secondSurface = model.geometry.surfaces[second.surfaceID] else {
            throw TopologyError.missingReference("A face is missing.")
        }
        let planes = DefaultPlanarSurfaceResolver()
        if let p = try planes.exactPlane(for: firstSurface, tolerance: tolerance, using: &execution), let q = try planes.exactPlane(for: secondSurface, tolerance: tolerance, using: &execution) {
            let n = try p.normal.normalized(tolerance: tolerance.distance)
            let m = try q.normal.normalized(tolerance: tolerance.distance)
            let outwardN = first.orientation == .forward ? n : n * -1
            let outwardM = second.orientation == .forward ? m : m * -1
            return outwardN.cross(outwardM).length <= tolerance.angle && outwardN.dot(outwardM) > 0
                && abs((q.origin - p.origin).dot(n)) <= tolerance.distance
        }
        let sameSurface: Bool
        if first.surfaceID == second.surfaceID {
            sameSurface = true
        } else {
            try GeometryStructuralComparisonWork.charge(surface: firstSurface, using: &execution)
            try GeometryStructuralComparisonWork.charge(surface: secondSurface, using: &execution)
            sameSurface = firstSurface == secondSurface
        }
        guard sameSurface, first.orientation == second.orientation else { return false }
        // A periodic surface without a pole (a full revolve's cylinder, cone or torus quarters)
        // merges too, keeping the edge that closes the turn as its seam.
        if try isPeriodic(firstSurface, using: &execution) { return try SurfaceParameterTopology(surface: firstSurface, using: &execution).uSingularVValues.isEmpty }
        if case .bSpline = firstSurface { return true }
        return false
    }

    private func isPeriodic(_ surface: Surface3D, using execution: inout OriginalQueryExecution) throws -> Bool {
        let topology = try SurfaceParameterTopology(surface: surface, using: &execution)
        return topology.uPeriod != nil || topology.vPeriod != nil
    }

    /// Whether the edge's two uses on a periodic face lie a whole period apart in its chart.
    private func closesTurn(_ edgeID: EdgeID, uses: [Coedge], face faceID: FaceID, model: BRepModel,
                            tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
        guard uses.count == 2, let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID],
              try isPeriodic(surface, using: &execution), let first = uses[0].surfaceParameterCurve, let second = uses[1].surfaceParameterCurve else {
            return false
        }
        return try PeriodicFaceSeamValidator().certifiesOppositeSeamCurves(first, second, on: surface, tolerance: tolerance, maximumSubdivisionDepth: 32, remainingSourceDepth: 16, maximumAlgebraicDepth: 32, using: &execution)
    }

    /// How far a face runs round a u-periodic surface: the span of its constant-v parameter curves.
    private func uExtent(of faceID: FaceID, model: BRepModel, using execution: inout OriginalQueryExecution) throws -> Double {
        var values: [Double] = []
        for loopID in model.faces[faceID]?.loops ?? [] {
            try execution.consumeWork(1)
            for coedge in model.loops[loopID]?.coedges ?? [] {
                try execution.consumeWork(1)
                if case let .constantV(_, start, end)? = coedge.surfaceParameterCurve {
                    try OriginalParameterQueryStorage.append(start, to: &values, using: &execution)
                    try OriginalParameterQueryStorage.append(end, to: &values, using: &execution)
                }
            }
        }
        guard let extent = try OriginalParameterQueryStorage.extrema(values, using: &execution, projection: { value, execution in value }) else { return 0 }
        return extent.upper - extent.lower
    }

    /// `kept` (some of `loop`'s coedges) with each constant-u parameter curve moved by whole
    /// periods to meet the constant-v curve before it in the loop, so a face whose side edge was
    /// written at the chart's other end reads continuously.
    private func continuousInChart(_ kept: [Coedge], of loop: [Coedge], period: Double, using execution: inout OriginalQueryExecution) throws -> [Coedge] {
        try OriginalParameterQueryStorage.map(kept, using: &execution) { coedge, execution in
            guard case let .constantU(u, vStart, vEnd)? = coedge.surfaceParameterCurve,
                  let index = try OriginalParameterQueryStorage.firstIndex(loop, using: &execution, predicate: { value, execution in value == coedge }) else { return coedge }
            let neighbours = [loop[(index + loop.count - 1) % loop.count], loop[(index + 1) % loop.count]]
            for neighbour in neighbours {
                try execution.consumeWork(1)
                guard case let .constantV(_, start, end)? = neighbour.surfaceParameterCurve else { continue }
                for value in [start, end] where abs(value - u) > 1e-9 && abs((value - u).remainder(dividingBy: period)) <= 1e-9 {
                    try execution.consumeWork(1)
                    var moved = coedge
                    moved.surfaceParameterCurve = .constantU(u: value, vStart: vStart, vEnd: vEnd)
                    return moved
                }
                return coedge
            }
            return coedge
        }
    }

    /// The coedges joined into closed loops where a vertex offers several ways on (a seam's ends),
    /// each next coedge the one whose parameter curve starts where the last one ends.
    private func chainByParameter(_ coedges: [Coedge], model: BRepModel, using execution: inout OriginalQueryExecution) throws -> [[Coedge]]? {
        func ends(_ coedge: Coedge, using execution: inout OriginalQueryExecution) throws -> (start: VertexID, end: VertexID) {
            try execution.consumeWork(1)
            guard let edge = model.edges[coedge.edgeID] else { throw TopologyError.missingReference("An edge is missing.") }
            return coedge.orientation == .forward ? (edge.startVertexID, edge.endVertexID) : (edge.endVertexID, edge.startVertexID)
        }
        func parameter(_ coedge: Coedge, atStart: Bool) -> (Double, Double)? {
            switch coedge.surfaceParameterCurve {
            case let .constantU(u, start, end)?: return (u, atStart ? start : end)
            case let .constantV(v, start, end)?: return (atStart ? start : end, v)
            default: return nil
            }
        }
        var outgoing: [VertexID: [Int]] = [:]
        for (index, coedge) in coedges.enumerated() { try append(index, for: try ends(coedge, using: &execution).start, in: &outgoing, using: &execution) }
        var used = Set<Int>()
        var loops: [[Coedge]] = []
        for start in coedges.indices where used.contains(start) == false {
            try execution.consumeWork(1)
            var loop: [Coedge] = []
            var index = start
            while try OriginalParameterQueryStorage.insert(index, in: &used, using: &execution) {
                try OriginalParameterQueryStorage.append(coedges[index], to: &loop, using: &execution)
                let candidates = try OriginalParameterQueryStorage.filter(outgoing[try ends(coedges[index], using: &execution).end] ?? [], using: &execution) { value, execution in !used.contains(value) || value == start }
                if candidates.count == 1 {
                    index = candidates[0]
                    continue
                }
                guard let here = parameter(coedges[index], atStart: false), let next = try OriginalParameterQueryStorage.first(candidates, using: &execution, predicate: { candidate, execution in
                    guard let there = parameter(coedges[candidate], atStart: true) else { return false }
                    return abs(there.0 - here.0) <= 1e-9 && abs(there.1 - here.1) <= 1e-9
                }) else { return nil }
                index = next
            }
            guard index == start else { return nil }
            try OriginalParameterQueryStorage.append(loop, to: &loops, using: &execution)
        }
        return loops
    }

    /// The coedges joined end to start into closed loops; nil when a vertex offers more than one
    /// way on, so the loops are not determined.
    private func chain(_ coedges: [Coedge], model: BRepModel, using execution: inout OriginalQueryExecution) throws -> [[Coedge]]? {
        func ends(_ coedge: Coedge, using execution: inout OriginalQueryExecution) throws -> (start: VertexID, end: VertexID) {
            try execution.consumeWork(1)
            guard let edge = model.edges[coedge.edgeID] else { throw TopologyError.missingReference("An edge is missing.") }
            return coedge.orientation == .forward ? (edge.startVertexID, edge.endVertexID) : (edge.endVertexID, edge.startVertexID)
        }
        var outgoing: [VertexID: [Int]] = [:]
        for (index, coedge) in coedges.enumerated() { try append(index, for: try ends(coedge, using: &execution).start, in: &outgoing, using: &execution) }
        guard try OriginalParameterQueryStorage.allSatisfy(outgoing.values, using: &execution, predicate: { value, execution in value.count == 1 }) else { return nil }
        var used = Set<Int>()
        var loops: [[Coedge]] = []
        for start in coedges.indices where used.contains(start) == false {
            try execution.consumeWork(1)
            var loop: [Coedge] = []
            var index = start
            while try OriginalParameterQueryStorage.insert(index, in: &used, using: &execution) {
                try OriginalParameterQueryStorage.append(coedges[index], to: &loop, using: &execution)
                guard let next = outgoing[try ends(coedges[index], using: &execution).end]?.first else { return nil }
                index = next
            }
            guard index == start else { return nil }
            try OriginalParameterQueryStorage.append(loop, to: &loops, using: &execution)
        }
        return loops
    }

    /// The area a loop encloses on a surface, from its points' surface parameters.
    private func enclosedArea(of loop: [Coedge], on surface: Surface3D, model: BRepModel, solver: BRepSurfaceMeetingSolver, using execution: inout OriginalQueryExecution) throws -> Double {
        var parameters: [(Double, Double)] = []
        for coedge in loop {
            try execution.consumeWork(1)
            guard let edge = model.edges[coedge.edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
                throw TopologyError.missingReference("An edge's geometry is missing.")
            }
            let (from, to) = coedge.orientation == .forward ? (trim.startParameter, trim.endParameter) : (trim.endParameter, trim.startParameter)
            for step in 0..<8 {
                try execution.consumeWork(1)
                let point = try curve.point(at: from + (to - from) * Double(step) / 8, tolerance: solver.tolerance, using: &execution)
                guard case let .projected(projection) = try surface.parameterProjectionResult(of: point, tolerance: solver.tolerance, using: &execution) else {
                    throw TopologyError.missingReference("A loop leaves its face's surface.")
                }
                try OriginalParameterQueryStorage.append((projection.u, projection.v), to: &parameters, using: &execution)
            }
        }
        let twice = try OriginalParameterQueryStorage.reduce(parameters.indices, initial: 0.0, using: &execution) { sum, index, execution in
            let (a, b) = (parameters[index], parameters[(index + 1) % parameters.count])
            return sum + a.0 * b.1 - b.0 * a.1
        }
        return abs(twice) / 2
    }

    // MARK: Edges

    private func mergeEdges(bodyID: BodyID, featureID: FeatureID, model: inout BRepModel, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
        let solver = BRepSurfaceMeetingSolver(tolerance: tolerance)
        var changed = false
        // Vertices whose edges cannot run on through them, which stay.
        var kept = Set<VertexID>()
        while true {
            try execution.consumeWork(1)
            let scope = try BodyTopologyScope(bodyID: bodyID, model: model, using: &execution)
            var facesOfEdge: [EdgeID: [FaceID]] = [:]
            var loopsOfEdge: [EdgeID: [LoopID]] = [:]
            for case let .face(faceID) in scope.references {
                try execution.consumeWork(1)
                for loopID in model.faces[faceID]?.loops ?? [] {
                    try execution.consumeWork(1)
                    for coedge in model.loops[loopID]?.coedges ?? [] {
                        try execution.consumeWork(1)
                        try append(faceID, for: coedge.edgeID, in: &facesOfEdge, using: &execution)
                        try append(loopID, for: coedge.edgeID, in: &loopsOfEdge, using: &execution)
                    }
                }
            }
            var edgesOfVertex: [VertexID: [EdgeID]] = [:]
            for edgeID in try OriginalParameterQueryStorage.ordered(facesOfEdge.keys, using: &execution, less: <) {
                try execution.consumeWork(1)
                guard let edge = model.edges[edgeID] else { continue }
                try append(edgeID, for: edge.startVertexID, in: &edgesOfVertex, using: &execution)
                if edge.endVertexID != edge.startVertexID { try append(edgeID, for: edge.endVertexID, in: &edgesOfVertex, using: &execution) }
            }
            // A vertex between just two edges on one curve, bounding the same faces.
            var merge: (vertex: VertexID, kept: EdgeID, gone: EdgeID)?
            for (vertexID, edges) in try OriginalParameterQueryStorage.ordered(edgesOfVertex, using: &execution, less: { $0.key < $1.key })
            where edges.count == 2 && edges[0] != edges[1] && kept.contains(vertexID) == false {
                let (a, b) = (edges[0], edges[1])
                guard try OriginalParameterQueryStorage.set(facesOfEdge[a] ?? [], using: &execution) == OriginalParameterQueryStorage.set(facesOfEdge[b] ?? [], using: &execution), (facesOfEdge[a] ?? []).count == (facesOfEdge[b] ?? []).count,
                      let first = model.edges[a], let second = model.edges[b],
                      // Two edges closing one curve stay two, since a closed edge needs a vertex of its own.
                      try OriginalParameterQueryStorage.set([first.startVertexID, first.endVertexID, second.startVertexID, second.endVertexID], using: &execution).count == 3,
                      try sameCarrier(a, b, model: model, tolerance: tolerance, using: &execution) else { continue }
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
            let sense = try solver.tangent(of: curve, at: keptTrim.startParameter, using: &execution) * (keptTrim.endParameter >= keptTrim.startParameter ? 1 : -1)
            if runOn.startVertexID == merge.vertex {
                runOn.startVertexID = far
            } else {
                runOn.endVertexID = far
            }
            guard let start = model.vertices[runOn.startVertexID]?.point, let end = model.vertices[runOn.endVertexID]?.point,
                  var trim = try solver.trim(curve, from: start, to: end, isClosed: false, sense: sense, using: &execution) else {
                try OriginalParameterQueryStorage.insert(merge.vertex, in: &kept, using: &execution)
                continue
            }
            // On a periodic curve the run keeps the kept edge's way round: an end read at the
            // period's other side moves by a whole period.
            if case let .periodic(period) = curve.parameterDomain {
                let increasing = keptTrim.endParameter >= keptTrim.startParameter
                if increasing, trim.endParameter < trim.startParameter { trim.endParameter += period }
                if increasing == false, trim.endParameter > trim.startParameter { trim.endParameter -= period }
            }
            runOn.trim = trim
            try OriginalParameterQueryStorage.set(runOn, for: merge.kept, in: &model.edges, using: &execution)
            try execution.consumeWork(1)
            try execution.retainStorage(bytes: MemoryLayout<(EdgeID, Edge)>.stride)
            model.edges.removeValue(forKey: merge.gone)
            try execution.consumeWork(1)
            try execution.retainStorage(bytes: MemoryLayout<(VertexID, Vertex)>.stride)
            model.vertices.removeValue(forKey: merge.vertex)
            for loopID in loopsOfEdge[merge.gone] ?? [] {
                try execution.consumeWork(1)
                guard var loop = model.loops[loopID],
                      let keptIndex = try OriginalParameterQueryStorage.firstIndex(loop.coedges, using: &execution, predicate: { coedge, execution in coedge.edgeID == merge.kept }),
                      let goneIndex = try OriginalParameterQueryStorage.firstIndex(loop.coedges, using: &execution, predicate: { coedge, execution in coedge.edgeID == merge.gone }) else { continue }
                // The two parameter curves run on into one where they are isolines or polylines;
                // otherwise the merged edge's is rebuilt.
                let count = loop.coedges.count
                let (first, second) = (keptIndex + 1) % count == goneIndex
                    ? (loop.coedges[keptIndex].surfaceParameterCurve, loop.coedges[goneIndex].surfaceParameterCurve)
                    : (loop.coedges[goneIndex].surfaceParameterCurve, loop.coedges[keptIndex].surfaceParameterCurve)
                loop.coedges = try OriginalParameterQueryStorage.materialize(loop.coedges, using: &execution)
                loop.coedges[keptIndex].surfaceParameterCurve = try joined(first, second, using: &execution)
                try execution.consumeWork(loop.coedges.count - goneIndex)
                loop.coedges.remove(at: goneIndex)
                try OriginalParameterQueryStorage.set(loop, for: loopID, in: &model.loops, using: &execution)
            }
            changed = true
        }
    }

    /// One parameter curve running through `first` and then `second`, when both are the same
    /// isoline or both polylines; nil otherwise.
    private func joined(_ first: SurfaceParameterCurve?, _ second: SurfaceParameterCurve?, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurve? {
        switch (first, second) {
        case let (.constantU(u1, start, _)?, .constantU(u2, _, end)?) where u1 == u2:
            return .constantU(u: u1, vStart: start, vEnd: end)
        case let (.constantV(v1, start, _)?, .constantV(v2, _, end)?) where v1 == v2:
            return .constantV(v: v1, uStart: start, uEnd: end)
        case let (.polyline(a)?, .polyline(b)?):
            var points = try OriginalParameterQueryStorage.materialize(a, using: &execution)
            for point in b.dropFirst() { try execution.consumeWork(1); try OriginalParameterQueryStorage.append(point, to: &points, using: &execution) }
            return .polyline(points)
        default:
            return nil
        }
    }

    /// Whether two edges lie on one curve: one line, one circle, or the same curve.
    private func sameCarrier(_ a: EdgeID, _ b: EdgeID, model: BRepModel, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
        guard let first = model.edges[a], let second = model.edges[b],
              let c1 = model.geometry.curves[first.curveID], let c2 = model.geometry.curves[second.curveID] else {
            throw TopologyError.missingReference("An edge is missing.")
        }
        if first.curveID == second.curveID { return true }
        try GeometryStructuralComparisonWork.charge(curve: c1, using: &execution)
        try GeometryStructuralComparisonWork.charge(curve: c2, using: &execution)
        if c1 == c2 { return true }
        let solver = BRepSurfaceMeetingSolver(tolerance: tolerance)
        // Each edge's ends lie on the other's curve, and at the shared vertex they run on.
        let ends = try OriginalParameterQueryStorage.compactMap([first.startVertexID, first.endVertexID, second.startVertexID, second.endVertexID], using: &execution) { vertex, execution in model.vertices[vertex]?.point }
        switch (c1, c2) {
        case (.line, .line), (.analytic(.line), .analytic(.line)), (.line, .analytic(.line)), (.analytic(.line), .line):
            for point in ends where (try solver.closest(to: point, on: c1, using: &execution).point - point).length > tolerance.distance { return false }
            return true
        case (.circle(let p), .circle(let q)):
            return (p.center - q.center).length <= tolerance.distance && abs(p.radius - q.radius) <= tolerance.distance
                && p.normal.cross(q.normal).length <= tolerance.angle * max(p.normal.length, 1)
        default:
            return false
        }
    }
    private func append<Key: Hashable, Value>(_ value: Value, for key: Key,
        in values: inout [Key: [Value]], using execution: inout OriginalQueryExecution) throws {
        if values[key] == nil { try OriginalParameterQueryStorage.set([], for: key, in: &values, using: &execution) }
        let count = values[key]!.count
        let capacity = values[key]!.capacity
        if count == capacity {
            let doubled = capacity.multipliedReportingOverflow(by: 2)
            guard !doubled.overflow else { throw KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: nil, message: "Adjacency capacity overflow.") }
            let next = max(1, doubled.partialValue)
            try execution.retainStorage(count: next, stride: MemoryLayout<Value>.stride)
            values[key, default: []].reserveCapacity(next)
        }
        try execution.consumeWork(1)
        values[key, default: []].append(value)
    }

}
