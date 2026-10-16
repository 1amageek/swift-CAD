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
                  model: BRepModel, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        try execution.consumeWork(1)
        let first = try SourceBRepFacePatchBuilder().build(faceID: firstFaceID,
            stableID: "finite-area:first", from: model, sourceSubshapes: [:], tolerance: tolerance, using: &execution).patch
        let second = try SourceBRepFacePatchBuilder().build(faceID: secondFaceID,
            stableID: "finite-area:second", from: model, sourceSubshapes: [:], tolerance: tolerance, using: &execution).patch
        func spans(_ patch: BRepSewingFacePatch, using execution: inout OriginalQueryExecution) throws -> [Span] {
            var result: [Span] = []
            for loop in patch.loops {
                for edge in loop.edges {
                    try execution.consumeWork(1)
                    try OriginalParameterQueryStorage.append(Span(edge: edge, role: loop.role), to: &result, using: &execution)
                }
            }
            return result
        }
        let firstEdges = try spans(first, using: &execution)
        let secondEdges = try spans(second, using: &execution)
        try execution.retainKernelValues(count: firstEdges.count, stride: MemoryLayout<[Point3D]>.stride)
        try execution.retainKernelValues(count: secondEdges.count, stride: MemoryLayout<[Point3D]>.stride)
        var firstEvents = Array(repeating: [Point3D](), count: firstEdges.count)
        var secondEvents = Array(repeating: [Point3D](), count: secondEdges.count)
        let intersector = ExactTrimEdgeIntersector()
        for (i, a) in firstEdges.enumerated() {
            try CurrentTaskCancellationChecker().checkCancellation()
            for (j, b) in secondEdges.enumerated() {
                try execution.consumeWork(1)
                switch try intersector.intersections(a.edge, b.edge, sharedSurface: first.surface, tolerance: tolerance, using: &execution) {
                case .coincident:
                    try OriginalParameterQueryStorage.append(contentsOf: [b.edge.startPoint, b.edge.endPoint], to: &firstEvents[i], using: &execution)
                    try OriginalParameterQueryStorage.append(contentsOf: [a.edge.startPoint, a.edge.endPoint], to: &secondEvents[j], using: &execution)
                case .subdivisionPoints(let points):
                    try OriginalParameterQueryStorage.append(contentsOf: points, to: &firstEvents[i], using: &execution)
                    try OriginalParameterQueryStorage.append(contentsOf: points, to: &secondEvents[j], using: &execution)
                }
            }
        }
        let subdivider = BRepSewingEdgeSubdivider()
        func partition(_ spans: [Span], _ events: [[Point3D]],
            using execution: inout OriginalQueryExecution) throws -> [Span] {
            var result: [Span] = []
            for (index, span) in spans.enumerated() {
                try execution.consumeWork(1)
                for edge in try subdivider.subdivide(span.edge, at: events[index],
                    tolerance: tolerance, using: &execution) {
                    try OriginalParameterQueryStorage.append(Span(edge: edge, role: span.role), to: &result, using: &execution)
                }
            }
            return result
        }
        let firstSpans = try partition(firstEdges, firstEvents, using: &execution)
        let secondSpans = try partition(secondEdges, secondEvents, using: &execution)
        let containment = DefaultFacePointContainmentTester()
        for (own, other, otherID) in [(firstSpans, secondSpans, secondFaceID),
                                      (secondSpans, firstSpans, firstFaceID)] {
            for span in own {
                try execution.consumeWork(1)
                try CurrentTaskCancellationChecker().checkCancellation()
                let parameter = span.edge.startParameter + (span.edge.endParameter - span.edge.startParameter) * 0.5
                let point = try span.edge.curve.point(at: parameter, tolerance: tolerance, using: &execution)
                var boundary = false
                for opposite in other where try subdivider.contains(point, on: opposite.edge, tolerance: tolerance, using: &execution) {
                    boundary = true
                    break
                }
                // Complete boundary events make containment constant on this open interval.
                if !boundary, try containment.contains(point, on: otherID, in: model, tolerance: tolerance, using: &execution) {
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
                        orientation: .forward, tolerance: tolerance, using: &execution)
                        || matcher.matches(CurveSpanDefinition(span.edge), CurveSpanDefinition(opposite.edge),
                            orientation: .reversed, tolerance: tolerance, using: &execution) {
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
