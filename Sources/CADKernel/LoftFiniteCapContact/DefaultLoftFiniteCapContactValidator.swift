import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Admits Loft contacts only on the two faces' original shared topology.
public struct DefaultLoftFiniteCapContactValidator: LoftFiniteCapContactValidating {
    public init() {}

    public func validate(capFaceIDs: [FaceID], sideFaceIDs: [FaceID],
                         model: BRepModel, tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.kernelOriginal()
        try validate(capFaceIDs: capFaceIDs, sideFaceIDs: sideFaceIDs,
            model: model, tolerance: tolerance, using: &execution)
    }

    public func validate(capFaceIDs: [FaceID], sideFaceIDs: [FaceID],
                         model: BRepModel, tolerance: ModelingTolerance,
                         using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        guard Set(capFaceIDs).count == capFaceIDs.count,
              Set(sideFaceIDs).count == sideFaceIDs.count,
              Set(capFaceIDs).isDisjoint(with: Set(sideFaceIDs)) else {
            throw failure("Loft cap and side faces must be distinct original faces.", tolerance: tolerance)
        }
        let pairCount = capFaceIDs.count.multipliedReportingOverflow(by: sideFaceIDs.count)
        guard !pairCount.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainKernelValues(count: pairCount.partialValue,
            stride: MemoryLayout<BooleanFacePairCandidate>.stride)
        let pairs = try capFaceIDs.flatMap { cap in
            try execution.consumeWork(sideFaceIDs.count)
            return sideFaceIDs.map { BooleanFacePairCandidate(targetFaceID: cap, toolFaceID: $0) }
        }
        let pipeline = BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())
        let graph = try pipeline.completeIntersectionGraph(facePairs: pairs, model: model, tolerance: tolerance, using: &execution)
        let splits = try pipeline.uvSplitGraph(intersectionGraph: graph, model: model, tolerance: tolerance, using: &execution)
        for split in splits.splits {
            try execution.checkpoint()
            let first = try boundary(split.facePair.targetFaceID, model: model, tolerance: tolerance, using: &execution)
            let second = try boundary(split.facePair.toolFaceID, model: model, tolerance: tolerance, using: &execution)
            let sharedIDs = Set(first.keys).intersection(second.keys)
            let sharedEdges = sharedIDs.compactMap { first[$0] }
            let firstVertices = vertices(of: Set(first.keys), model: model)
            let secondVertices = vertices(of: Set(second.keys), model: model)
            let sharedPoints = firstVertices.intersection(secondVertices).compactMap { model.vertices[$0]?.point }
            for component in split.components {
                try execution.consumeWork(1)
                switch component.geometry {
                case .tangent(let point):
                    try admit(point.point, sharedPoints: sharedPoints, tolerance: tolerance, using: &execution)
                case .coincident:
                    if try FiniteCoincidentFaceAreaClassifier().overlaps(split.facePair.targetFaceID,
                        split.facePair.toolFaceID, model: model, tolerance: tolerance, using: &execution) {
                        throw failure("A Loft cap and side overlap in finite material area.", tolerance: tolerance)
                    }
                    try validateCoincidentContacts(first: first, second: second,
                        sharedEdges: sharedEdges, sharedPoints: sharedPoints, tolerance: tolerance, using: &execution)
                case .transverseSegment, .trimmedCurve, .closedCurve:
                    let reference = BooleanFaceSplitComponentReference(facePair: split.facePair, componentID: component.id)
                    let intersections = try BooleanFaceArrangementBoundary.edges(reference: reference,
                        geometry: component.geometry, faceID: split.facePair.targetFaceID, surfaceSide: .first,
                        parentSubshapeIDs: [], tolerance: tolerance, using: &execution)
                    for intersection in intersections {
                        guard try isSharedSubspan(intersection, of: sharedEdges, tolerance: tolerance, using: &execution) else {
                            throw failure("A finite Loft cap/side intersection leaves their original shared edges.", tolerance: tolerance)
                        }
                    }
                }
            }
        }
        try execution.checkpoint()
    }

    private func boundary(_ faceID: FaceID, model: BRepModel,
                          tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [EdgeID: BRepSewingEdge] {
        let patch = try SourceBRepFacePatchBuilder().build(faceID: faceID,
            stableID: "loft-contact:\(faceID)", from: model, sourceSubshapes: [:], tolerance: tolerance, using: &execution).patch
        guard let face = model.faces[faceID] else { throw TopologyError.missingReference("A Loft face is missing.") }
        var result: [EdgeID: BRepSewingEdge] = [:]
        for (loopID, loop) in zip(face.loops, patch.loops) {
            guard let source = model.loops[loopID], source.edges.count == loop.edges.count else {
                throw TopologyError.missingReference("A Loft source boundary is incomplete.")
            }
            try execution.retainKernelValues(count: source.edges.count,
                stride: MemoryLayout<(EdgeID, BRepSewingEdge)>.stride)
            for (use, edge) in zip(source.edges, loop.edges) {
                try execution.consumeWork(1)
                result[use.edgeID] = edge
            }
        }
        return result
    }

    private func vertices(of edges: Set<EdgeID>, model: BRepModel) -> Set<VertexID> {
        Set(edges.flatMap { id in
            guard let edge = model.edges[id] else { return [VertexID]() }
            return [edge.startVertexID, edge.endVertexID]
        })
    }

    private func admit(_ point: Point3D, sharedPoints: [Point3D],
                       tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(sharedPoints.count)
        guard sharedPoints.contains(where: { ($0 - point).length <= tolerance.distance }) else {
            throw failure("A finite Loft tangency is not an original shared vertex.", tolerance: tolerance)
        }
    }

    private func isSharedSubspan(_ candidate: BRepSewingEdge, of originals: [BRepSewingEdge],
                                 tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
        let subdivider = BRepSewingEdgeSubdivider()
        let matcher = CurveSpanCoincidenceMatcher()
        for original in originals {
            try execution.consumeWork(1)
            let pieces = try subdivider.subdivide(original,
                at: [candidate.startPoint, candidate.endPoint], tolerance: tolerance, using: &execution)
            for piece in pieces {
                if try matcher.matches(CurveSpanDefinition(candidate), CurveSpanDefinition(piece),
                    orientation: .forward, tolerance: tolerance, using: &execution)
                    || matcher.matches(CurveSpanDefinition(candidate), CurveSpanDefinition(piece),
                        orientation: .reversed, tolerance: tolerance, using: &execution) { return true }
            }
        }
        return false
    }

    private func validateCoincidentContacts(first: [EdgeID: BRepSewingEdge], second: [EdgeID: BRepSewingEdge],
                                           sharedEdges: [BRepSewingEdge], sharedPoints: [Point3D],
                                           tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        let intersector = ExactTrimEdgeIntersector()
        let subdivider = BRepSewingEdgeSubdivider()
        let matcher = CurveSpanCoincidenceMatcher()
        for firstID in first.keys.sorted() {
            guard let a = first[firstID] else { continue }
            for secondID in second.keys.sorted() {
                try execution.consumeWork(1)
                guard let b = second[secondID] else { continue }
                switch try intersector.intersections(a, b, tolerance: tolerance, using: &execution) {
                case .coincident:
                    guard try isSharedSubspan(a, of: sharedEdges, tolerance: tolerance, using: &execution) else {
                        throw failure("Coincident Loft boundaries are not an original shared edge.", tolerance: tolerance)
                    }
                case .subdivisionPoints(let points):
                    for point in points { try admit(point, sharedPoints: sharedPoints, tolerance: tolerance, using: &execution) }
                    let aPieces = try subdivider.subdivide(a, at: points, tolerance: tolerance, using: &execution)
                    let bPieces = try subdivider.subdivide(b, at: points, tolerance: tolerance, using: &execution)
                    for aPiece in aPieces {
                        for bPiece in bPieces {
                            if try matcher.matches(CurveSpanDefinition(aPiece), CurveSpanDefinition(bPiece),
                                orientation: .forward, tolerance: tolerance, using: &execution)
                                || matcher.matches(CurveSpanDefinition(aPiece), CurveSpanDefinition(bPiece),
                                    orientation: .reversed, tolerance: tolerance, using: &execution) {
                                guard try isSharedSubspan(aPiece, of: sharedEdges, tolerance: tolerance, using: &execution) else {
                                    throw failure("A partial coincident Loft contact is not original shared topology.", tolerance: tolerance)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func failure(_ message: String, tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance, message: message)
    }
}
