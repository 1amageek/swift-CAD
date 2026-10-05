import CADCore
import CADGeometry
import CADModeling
import CADTopology

/// Classifies finite area only after complete original boundary-event isolation.
struct FiniteCoincidentFaceAreaClassifier {
    private struct Span {
        let edge: BRepSewingEdge
        let role: LoopRole
    }

    func overlaps(_ firstFaceID: FaceID, _ secondFaceID: FaceID,
                  model: BRepModel, tolerance: ModelingTolerance) throws -> Bool {
        let first = try SourceBRepFacePatchBuilder().build(faceID: firstFaceID,
            stableID: "finite-area:first", from: model, sourceSubshapes: [:], tolerance: tolerance).patch
        let second = try SourceBRepFacePatchBuilder().build(faceID: secondFaceID,
            stableID: "finite-area:second", from: model, sourceSubshapes: [:], tolerance: tolerance).patch
        let firstEdges = first.loops.flatMap { loop in loop.edges.map { Span(edge: $0, role: loop.role) } }
        let secondEdges = second.loops.flatMap { loop in loop.edges.map { Span(edge: $0, role: loop.role) } }
        var firstEvents = Array(repeating: [Point3D](), count: firstEdges.count)
        var secondEvents = Array(repeating: [Point3D](), count: secondEdges.count)
        let intersector = ExactTrimEdgeIntersector()
        for (i, a) in firstEdges.enumerated() {
            try CurrentTaskCancellationChecker().checkCancellation()
            for (j, b) in secondEdges.enumerated() {
                switch try intersector.intersections(a.edge, b.edge, sharedSurface: first.surface, tolerance: tolerance) {
                case .coincident:
                    firstEvents[i] += [b.edge.startPoint, b.edge.endPoint]
                    secondEvents[j] += [a.edge.startPoint, a.edge.endPoint]
                case .subdivisionPoints(let points):
                    firstEvents[i] += points
                    secondEvents[j] += points
                }
            }
        }
        let subdivider = BRepSewingEdgeSubdivider()
        func partition(_ spans: [Span], _ events: [[Point3D]]) throws -> [Span] {
            try spans.enumerated().flatMap { index, span in
                try subdivider.subdivide(span.edge, at: events[index], tolerance: tolerance).map {
                    Span(edge: $0, role: span.role)
                }
            }
        }
        let firstSpans = try partition(firstEdges, firstEvents)
        let secondSpans = try partition(secondEdges, secondEvents)
        let containment = DefaultFacePointContainmentTester()
        for (own, other, otherID) in [(firstSpans, secondSpans, secondFaceID),
                                      (secondSpans, firstSpans, firstFaceID)] {
            for span in own {
                try CurrentTaskCancellationChecker().checkCancellation()
                let parameter = span.edge.startParameter + (span.edge.endParameter - span.edge.startParameter) * 0.5
                let point = try span.edge.curve.point(at: parameter, tolerance: tolerance)
                var boundary = false
                for opposite in other where try subdivider.contains(point, on: opposite.edge, tolerance: tolerance) {
                    boundary = true
                    break
                }
                // Complete boundary events make containment constant on this open interval.
                if !boundary, try containment.contains(point, on: otherID, in: model, tolerance: tolerance) {
                    return true
                }
            }
        }
        // When the complete outer boundary is shared, both finite domains own its
        // interior. An opposing hole owns its exterior and does not establish area.
        let matcher = CurveSpanCoincidenceMatcher()
        for (own, other) in [(firstSpans, secondSpans), (secondSpans, firstSpans)] {
            let outer = own.filter { $0.role == .outer }
            guard !outer.isEmpty else { continue }
            var covered = true
            for span in outer {
                var matchedOuter = false
                for opposite in other where opposite.role == .outer {
                    if try matcher.matches(CurveSpanDefinition(span.edge), CurveSpanDefinition(opposite.edge),
                        orientation: .forward, tolerance: tolerance)
                        || matcher.matches(CurveSpanDefinition(span.edge), CurveSpanDefinition(opposite.edge),
                            orientation: .reversed, tolerance: tolerance) {
                        matchedOuter = true
                        break
                    }
                }
                if !matchedOuter { covered = false; break }
            }
            if covered { return true }
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return false
    }
}
