import HashTreeCollections
import CADCore
import CADGeometry

/// Restores exact parameter incidence omitted at an original collapsed boundary.
struct OriginalCollapsedWireRestorer {
    func restore(model: inout BRepModel, tolerance: ModelingTolerance,
        changes: inout [BRepRepairChange], diagnostics: inout [BRepRepairDiagnostic]) throws {
        var execution = try BRepModel.originalValidationExecution()
        try restore(model: &model, tolerance: tolerance, changes: &changes,
            diagnostics: &diagnostics, using: &execution)
    }

    func restore(model: inout BRepModel, tolerance: ModelingTolerance,
        changes: inout [BRepRepairChange], diagnostics: inout [BRepRepairDiagnostic],
        using execution: inout OriginalQueryExecution) throws {
        var faceIDs = try OriginalParameterQueryStorage.map(model.faces.keys, using: &execution) { id, execution in id }
        try OriginalParameterQueryStorage.sort(&faceIDs, using: &execution, less: <)
        for faceID in faceIDs {
            try execution.consumeWork(1)
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else { continue }
            for loopID in face.loops {
                guard var loop = model.loops[loopID], !loop.coedges.isEmpty else { continue }
                let original = loop.coedges
                var restored: [Coedge] = []
                for index in original.indices {
                    try execution.consumeWork(1)
                    let previous = original[index]
                    let next = original[(index+1)%original.count]
                    try OriginalParameterQueryStorage.append(previous, to: &restored, using: &execution)
                    guard let a = previous.surfaceParameterCurve, let b = next.surfaceParameterCurve,
                        let previousEdge = model.edges[previous.edgeID], let nextEdge = model.edges[next.edgeID] else { continue }
                    let endVertex = previous.orientation == .forward ? previousEdge.endVertexID : previousEdge.startVertexID
                    let startVertex = next.orientation == .forward ? nextEdge.startVertexID : nextEdge.endVertexID
                    guard endVertex == startVertex, let vertex = model.vertices[endVertex] else { continue }
                    let end = try a.endParameter(tolerance: tolerance, using: &execution), start = try b.startParameter(tolerance: tolerance, using: &execution)
                    guard end != start else { continue }
                    let pcurve: SurfaceParameterCurve
                    let direction: OriginalBSplinePoleNormal.Direction
                    if end.u == start.u, end.v != start.v {
                        pcurve = .constantU(u: end.u, vStart: end.v, vEnd: start.v); direction = .constantU
                    } else if end.v == start.v, end.u != start.u {
                        pcurve = .constantV(v: end.v, uStart: end.u, uEnd: start.u); direction = .constantV
                    } else { continue }
                    let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: surface, parameterCurve: pcurve))
                    guard try BRepEdgeGeometryClassifier().kind(curve: curve, from: 0, to: 1,
                        tolerance: tolerance, using: &execution) == .singular else { continue }
                    do {
                        let box = SurfaceParameterBox(u: try ScalarInterval(lower: min(end.u,start.u), upper: max(end.u,start.u)),
                            v: try ScalarInterval(lower: min(end.v,start.v), upper: max(end.v,start.v)))
                        let receipt = try OriginalSurfaceCollapsedBoundaryPoint.prepare(of: surface, over: box,
                            direction: direction, remainingSourceDepth: 16, tolerance: tolerance,
                            using: &execution)
                        let displacement = IntervalVector3DBounds(
                            x: receipt.positionBounds.x - .exact(vertex.point.x),
                            y: receipt.positionBounds.y - .exact(vertex.point.y),
                            z: receipt.positionBounds.z - .exact(vertex.point.z)).lengthUpperBound
                        guard displacement.isFinite, displacement <= tolerance.distance * 8 else {
                            throw TopologyError.invalidEdge(previous.edgeID)
                        }
                        let curveID = CurveID(), edgeID = EdgeID()
                        try execution.retainStorage(bytes: MemoryLayout<(CurveID, Curve3D)>.stride)
                        model.geometry.curves[curveID] = curve
                        try execution.retainStorage(bytes: MemoryLayout<(EdgeID, Edge)>.stride)
                        model.edges[edgeID] = Edge(id: edgeID, curveID: curveID, startVertexID: endVertex,
                            endVertexID: endVertex, trim: CurveTrim(startParameter: 0, endParameter: 1))
                        try OriginalParameterQueryStorage.append(Coedge(edgeID: edgeID, surfaceParameterCurve: pcurve), to: &restored, using: &execution)
                        try execution.retainStorage(bytes: 4 * MemoryLayout<String>.stride)
                        try OriginalParameterQueryStorage.append(.init(action: .restoreSingularBoundaryUses, scope: .pcurves,
                            affectedEntityIDs: [String(describing: loopID), String(describing: edgeID)],
                            message: "Restored original collapsed boundary parameter incidence without moving its shared vertex.",
                            generatedEntityIDs: [String(describing: curveID), String(describing: edgeID)]), to: &changes, using: &execution)
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        let failure = try OriginalTopologyValidationFinding.classify(error, tolerance: tolerance)
                        try OriginalParameterQueryStorage.append(.init(action: .restoreSingularBoundaryUses, code: .topologyFailure,
                            entityID: String(describing: loopID),
                            message: "Original collapsed boundary position could not authorize its omitted use: \(failure.message)."), to: &diagnostics, using: &execution)
                    }
                }
                loop.coedges = restored
                try execution.retainStorage(bytes: MemoryLayout<(LoopID, Loop)>.stride)
                model.loops[loopID] = loop
            }
        }
    }
}
