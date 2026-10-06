import CADCore
import CADGeometry
import CADIR
import CADTopology
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif

public struct BRepDrawingHatcher: BRepDrawingHatching {
    private struct Boundary {
        let bodyID: BodyID
        let curve: Curve3D
        let range: ScalarInterval
    }
    private let intersections: any CurveSurfaceIntersectionResolving
    private let classifier: any SolidPointClassifying
    private let containment: any FacePointContainmentTesting

    public init(intersections: any CurveSurfaceIntersectionResolving = DefaultCurveSurfaceIntersector(),
                classifier: any SolidPointClassifying = DefaultBRepSolidPointClassifier(),
                containment: any FacePointContainmentTesting = DefaultFacePointContainmentTester()) {
        self.intersections = intersections; self.classifier = classifier; self.containment = containment
    }

    public func hatch(_ section: BRepDrawingSection, in evaluated: EvaluatedDocument,
                      spacing: Double, maximumRows: Int, maximumBoundaryCurves: Int,
                      maximumEventsPerRow: Int, maximumSegments: Int) throws -> [BRepDrawingHatchSegment] {
        try hatchPrepared(section, in: evaluated, spacing: spacing, maximumRows: maximumRows,
            maximumBoundaryCurves: maximumBoundaryCurves, maximumEventsPerRow: maximumEventsPerRow,
            maximumSegments: maximumSegments, originalCutting: nil)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): The original cutting-chart row algorithm
    // is source-connected, but production lower intersection/classifier sessions
    // still need complete caller work/storage forwarding before aggregate closure.
    public func hatch(_ section: BRepDrawingSection, in evaluated: EvaluatedDocument,
                      spacing: Double, maximumRows: Int, maximumBoundaryCurves: Int,
                      maximumEventsPerRow: Int, maximumSegments: Int,
                      maximumPreparationWork: Int, maximumPreparationBytes: Int,
                      maximumSourceDepth: Int, maximumSubdivisionDepth: Int,
                      maximumAlgebraicDepth: Int) throws -> BRepDrawingHatchResult {
        let tolerance = evaluated.configuration.tolerance
        try section.validateCurrent(evaluated)
        guard maximumPreparationWork > 0, maximumPreparationBytes > 0,
              let support = section.cuttingSupport else {
            throw failure(.invalidInput, "The preparation-bounded hatch invocation requires an original cutting support and positive capacities.", tolerance)
        }
        let admission = BRepDrawingCuttingAdmission(owner: .init(maximumWork: maximumPreparationWork,
            maximumBytes: maximumPreparationBytes, tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth))
        let prepared = try PreparedBRepDrawingHatchSupport(support, tolerance: tolerance,
            maximumSourceDepth: maximumSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, usage: admission)
        let segments = try hatchPrepared(section, in: evaluated, spacing: spacing, maximumRows: maximumRows,
            maximumBoundaryCurves: maximumBoundaryCurves, maximumEventsPerRow: maximumEventsPerRow,
            maximumSegments: maximumSegments, originalCutting: prepared)
        return BRepDrawingHatchResult(segments: segments, consumedPreparationWork: admission.consumedWork,
            retainedPreparationBytes: admission.retainedBytes)
    }

    private func hatchPrepared(_ section: BRepDrawingSection, in evaluated: EvaluatedDocument,
                      spacing: Double, maximumRows: Int, maximumBoundaryCurves: Int,
                      maximumEventsPerRow: Int, maximumSegments: Int,
                      originalCutting: PreparedBRepDrawingHatchSupport?) throws -> [BRepDrawingHatchSegment] {
        var cutting = originalCutting
        let tolerance = evaluated.configuration.tolerance
        try section.validateCurrent(evaluated)
        // FIXME(INCOMPLETE_IMPLEMENTATION): The legacy hatch invocation has no original
        // cutting-support preparation ledger. A placed local-plane section must use
        // complete original UV row/event discovery before publishing hatch spans;
        // its output projection frame is not a substitute cutting chart.
        guard section.cuttingSupport == nil || cutting != nil else {
            throw failure(.intersectionFailure, "Original placed cutting-support hatch event discovery is incomplete.", tolerance)
        }
        let sourceSnapshot = BRepDrawingSourceSnapshot(evaluated)
        let working = section.workingBRep
        guard spacing.isFinite, spacing > (cutting == nil ? tolerance.distance : 0), maximumRows > 0,
              maximumBoundaryCurves > 0, maximumEventsPerRow >= 2, maximumSegments > 0 else {
            throw failure(.invalidInput, "Section hatch spacing and capacities are invalid.", tolerance)
        }
        guard let horizontal = section.horizontalRange, let vertical = section.verticalRange else {
            guard section.components.isEmpty else { throw failure(.missingReference, "Section bounds are absent.", tolerance) }
            return []
        }
        var boundaries: [Boundary] = []
        var coincidentFaces: [BodyID: Set<FaceID>] = [:]
        func append(_ body: BodyID, _ curve: Curve3D, _ start: Double, _ end: Double) throws {
            guard boundaries.count < maximumBoundaryCurves else {
                throw failure(.resourceLimitExceeded, "Hatch boundary-curve capacity exhausted.", tolerance)
            }
            try cutting?.usage.consume(work: 1)
            try cutting?.usage.retain(1, of: Boundary.self)
            boundaries.append(Boundary(bodyID: body, curve: curve,
                range: try ScalarInterval(lower: min(start, end), upper: max(start, end))))
        }
        for component in section.components {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard working.bodies[component.bodyID]?.kind == .solid else { continue }
            switch component.geometry {
            case .transverseSegment(let start, let end):
                let direction = end.point - start.point
                try append(component.bodyID, .line(Line3D(origin: start.point,
                    direction: direction.normalized(tolerance: tolerance.distance))), 0, direction.length)
            case .closedCurve(let closed):
                let range = try BodySectionCurveEvaluator.closedRange(of: closed.intersection.curve, tolerance: tolerance)
                try append(component.bodyID, closed.intersection.curve, range.lower, range.upper)
            case .trimmedCurve(let chain):
                for segment in chain.segments { try append(component.bodyID, segment.intersection.curve,
                    segment.startParameter, segment.endParameter) }
            case .coincident:
                coincidentFaces[component.bodyID, default: []].insert(component.faceID)
                guard let face = working.faces[component.faceID] else {
                    throw failure(.missingReference, "Coplanar section face is absent.", tolerance)
                }
                for loopID in face.loops {
                    guard let loop = working.loops[loopID] else {
                        throw failure(.missingReference, "Coplanar section loop is absent.", tolerance)
                    }
                    for coedge in loop.coedges {
                        let edge = try DefaultOrthographicEdgeProjector().project(edgeID: coedge.edgeID,
                            in: working, orientation: coedge.orientation, onto: section.frame, tolerance: tolerance)
                        try append(component.bodyID, edge.curve.source, edge.startParameter, edge.endParameter)
                    }
                }
            case .tangent: break
            }
        }
        let firstRow = ceil(vertical.lower / spacing) * spacing
        let rowCount = floor((vertical.upper - firstRow) / spacing) + 1
        guard firstRow.isFinite, rowCount.isFinite, rowCount >= 0,
              rowCount <= Double(maximumRows), let count = Int(exactly: rowCount) else {
            throw failure(.resourceLimitExceeded, "Hatch row allowance or numeric resolution exhausted.", tolerance)
        }
        let bodyIDs = Set(boundaries.map(\.bodyID)).sorted(by: { $0.description < $1.description })
        let sessions = try SolidPointClassificationSessionSet(bodyIDs: bodyIDs, pointClassifier: classifier,
            model: working, tolerance: tolerance)
        var output: [BRepDrawingHatchSegment] = []
        var previousY: Double?
        for row in 0..<count {
            try CurrentTaskCancellationChecker().checkCancellation()
            let y = firstRow + Double(row) * spacing
            guard y.isFinite else {
                throw failure(.resourceLimitExceeded, "Hatch row is nonfinite.", tolerance)
            }
            if let previousY, y <= previousY {
                throw failure(.resourceLimitExceeded, "Hatch row coordinates exhausted floating-point resolution.", tolerance)
            }
            previousY = y
            try cutting?.usage.consume(work: 1)
            let rowPlane: Surface3D
            if cutting != nil {
                rowPlane = try cutting!.row(at: y, tolerance: tolerance)
            } else {
                rowPlane = .plane(Plane3D(origin: section.frame.origin + section.frame.vertical * y, normal: section.frame.vertical))
            }
            var events: [BodyID: [Double]] = [:]
            var eventCount = 0
            func event(_ body: BodyID, _ point: Point3D, _ originalU: Double) throws {
                guard eventCount < maximumEventsPerRow else {
                    throw failure(.resourceLimitExceeded, "Hatch intersection-event capacity exhausted.", tolerance)
                }
                let x = cutting == nil ? try section.frame.project(point).x : originalU
                guard horizontal.contains(x) else {
                    throw failure(.invalidInput, "Hatch event escaped the retained original section envelope.", tolerance)
                }
                eventCount += 1
                try cutting?.usage.consume(work: 1)
                try cutting?.usage.retain(1, of: Double.self)
                events[body, default: []].append(x)
            }
            for boundary in boundaries {
                let result = try intersections.intersectionResult(curve: boundary.curve, surface: rowPlane,
                    options: CurveSurfaceIntersectionOptions(curveRange: boundary.range), tolerance: tolerance)
                for point in result.points { try event(boundary.bodyID, point.point, point.surfaceU) }
                for overlap in result.overlaps {
                    try event(boundary.bodyID, overlap.start.point, overlap.start.surfaceParameter.u)
                    try event(boundary.bodyID, overlap.end.point, overlap.end.surfaceParameter.u)
                }
            }
            for bodyID in bodyIDs {
                var cuts = events[bodyID] ?? []
                guard eventCount <= maximumEventsPerRow - 2 else {
                    throw failure(.resourceLimitExceeded, "Hatch interval endpoint allowance exhausted.", tolerance)
                }
                eventCount += 2
                cuts.append(horizontal.lower); cuts.append(horizontal.upper); cuts.sort()
                for index in 1..<cuts.count {
                    let lower = cuts[index - 1], upper = cuts[index]
                    if upper == lower { continue }
                    let middle = lower + (upper - lower) * 0.5
                    guard middle > lower, middle < upper else {
                        throw failure(.resourceLimitExceeded, "Hatch interval resolution exhausted.", tolerance)
                    }
                    let world: Point3D
                    if cutting != nil { world = try cutting!.point(u: middle, v: y) }
                    else { world = section.frame.origin + section.frame.horizontal * middle + section.frame.vertical * y }
                    let state = try sessions.classify(world, in: bodyID)
                    var admitted = state == .inside
                    if state == .boundary {
                        for faceID in coincidentFaces[bodyID] ?? [] {
                            if try containment.contains(world, on: faceID, in: working, tolerance: tolerance) {
                                admitted = true; break
                            }
                        }
                    }
                    if admitted {
                        guard output.count < maximumSegments else {
                            throw failure(.resourceLimitExceeded, "Hatch output-segment capacity exhausted.", tolerance)
                        }
                        try cutting?.usage.consume(work: 1)
                        try cutting?.usage.retain(1, of: BRepDrawingHatchSegment.self)
                        output.append(BRepDrawingHatchSegment(bodyID: bodyID, materialID: working.bodies[bodyID]?.material,
                            row: row, start: Point2D(x: lower, y: y), end: Point2D(x: upper, y: y), sourceSnapshot: sourceSnapshot, sectionIdentity: section.publicationIdentity, placement: section.placement))
                    }
                }
            }
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return output
    }
    private func failure(_ code: KernelError.Code, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
