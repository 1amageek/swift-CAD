import HashTreeCollections
import CADCore
import CADGeometry

/// Restores exact parameter incidence omitted at an original collapsed boundary.
struct OriginalCollapsedWireRestorer {
    func restore(model: inout BRepModel, tolerance: ModelingTolerance,
        changes: inout [BRepRepairChange], diagnostics: inout [BRepRepairDiagnostic]) throws {
        for faceID in model.faces.keys.sorted() {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else { continue }
            for loopID in face.loops {
                guard var loop = model.loops[loopID], !loop.coedges.isEmpty else { continue }
                let original = loop.coedges
                var restored: [Coedge] = []
                for index in original.indices {
                    try CurrentTaskCancellationChecker().checkCancellation()
                    let previous = original[index]
                    let next = original[(index+1)%original.count]
                    restored.append(previous)
                    guard let a = previous.surfaceParameterCurve, let b = next.surfaceParameterCurve,
                        let previousEdge = model.edges[previous.edgeID], let nextEdge = model.edges[next.edgeID] else { continue }
                    let endVertex = previous.orientation == .forward ? previousEdge.endVertexID : previousEdge.startVertexID
                    let startVertex = next.orientation == .forward ? nextEdge.startVertexID : nextEdge.endVertexID
                    guard endVertex == startVertex, let vertex = model.vertices[endVertex] else { continue }
                    let end = try a.endParameter(tolerance: tolerance), start = try b.startParameter(tolerance: tolerance)
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
                        tolerance: tolerance) == .singular else { continue }
                    do {
                        let box = SurfaceParameterBox(u: try ScalarInterval(lower: min(end.u,start.u), upper: max(end.u,start.u)),
                            v: try ScalarInterval(lower: min(end.v,start.v), upper: max(end.v,start.v)))
                        let receipt = try OriginalSurfaceCollapsedBoundaryPoint.prepare(of: surface, over: box,
                            direction: direction, remainingSourceDepth: 16, tolerance: tolerance,
                            consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() })
                        let displacement = IntervalVector3DBounds(
                            x: receipt.positionBounds.x - .exact(vertex.point.x),
                            y: receipt.positionBounds.y - .exact(vertex.point.y),
                            z: receipt.positionBounds.z - .exact(vertex.point.z)).lengthUpperBound
                        guard displacement.isFinite, displacement <= tolerance.distance * 8 else {
                            throw TopologyError.invalidEdge(previous.edgeID)
                        }
                        let curveID = CurveID(), edgeID = EdgeID()
                        model.geometry.curves[curveID] = curve
                        model.edges[edgeID] = Edge(id: edgeID, curveID: curveID, startVertexID: endVertex,
                            endVertexID: endVertex, trim: CurveTrim(startParameter: 0, endParameter: 1))
                        restored.append(Coedge(edgeID: edgeID, surfaceParameterCurve: pcurve))
                        changes.append(.init(action: .restoreSingularBoundaryUses, scope: .pcurves,
                            affectedEntityIDs: [String(describing: loopID), String(describing: edgeID)],
                            message: "Restored original collapsed boundary parameter incidence without moving its shared vertex.",
                            generatedEntityIDs: [String(describing: curveID), String(describing: edgeID)]))
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        diagnostics.append(.init(action: .restoreSingularBoundaryUses, code: .topologyFailure,
                            entityID: String(describing: loopID),
                            message: "Original collapsed boundary position could not authorize its omitted use: \(KernelError.wrapping(error, phase: .topology, tolerance: tolerance).message)."))
                    }
                }
                loop.coedges = restored
                model.loops[loopID] = loop
            }
        }
    }
}
