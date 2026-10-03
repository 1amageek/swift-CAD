import Foundation
import CADCore
import CADGeometry
import CADIR

/// Patch from closed curves: the curves joined end to end into one closed loop (or one closed
/// curve) and the sheet spanning it — the exact trimmed plane of a planar loop, the exact Coons
/// patch of a loop with at most four corners, or the `loopFiller`'s smooth trimmed sheet of a loop
/// with more.
public struct CurvePatchFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let sewer: any BRepSewing
    private let surfaceFill: SurfaceFillFeatureEvaluator
    private let sheetEvaluator = BSplineSurfaceFeatureEvaluator()
    private let loopFiller: (any CurveLoopFilling)?

    public init(sewer: any BRepSewing) {
        self.init(sewer: sewer, loopFiller: nil)
    }

    package init(sewer: any BRepSewing, loopFiller: (any CurveLoopFilling)?) {
        self.sewer = sewer
        surfaceFill = SurfaceFillFeatureEvaluator(sewer: sewer)
        self.loopFiller = loopFiller
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try evaluateUnvalidated(feature: feature, context: context)
        }
    }

    private func evaluateUnvalidated(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        let tolerance = context.tolerance
        guard case let .curvePatch(patch) = feature.operation else {
            throw KernelError(phase: .validation, code: .invalidInput, featureID: feature.id, tolerance: tolerance,
                              message: "CurvePatchFeatureEvaluator requires a curve patch feature.")
        }
        try patch.validate()
        func failure(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .invalidInput, featureID: feature.id, tolerance: tolerance, message: message)
        }
        // Every curve's exact spans, joined end to end from the first curve.
        var pieces = try patch.curves.map { reference -> [BSplineCurve3D] in
            let curve = try ResolvedModelingSection.resolveCurve(reference, from: context.curves[reference.featureID], tolerance: tolerance)
            return try ExactBSplineCurveSpanBuilder(tolerance: tolerance).sectionSpans(from: curve).map(\.curve)
        }
        func ends(_ spans: [BSplineCurve3D]) throws -> (Point3D, Point3D) {
            guard let first = spans.first, let last = spans.last,
                  case let .closed(lower, _) = first.domain, case let .closed(_, upper) = last.domain else {
                throw failure("A curve patch's curve has no bounded span.")
            }
            return (try Curve3D.bSpline(first).point(at: lower, tolerance: tolerance),
                    try Curve3D.bSpline(last).point(at: upper, tolerance: tolerance))
        }
        // Curves that cross instead of meeting end to end bound the region between their crossings:
        // each is cut between its crossings with the two curves beside it, its overhangs left out.
        let allEnds = try pieces.map { try ends($0) }
        let meetsEndToEnd = allEnds.indices.allSatisfy { index in
            [allEnds[index].0, allEnds[index].1].allSatisfy { point in
                allEnds.indices.contains { other in
                    other != index && ((allEnds[other].0 - point).length <= tolerance.distance
                        || (allEnds[other].1 - point).length <= tolerance.distance)
                }
            }
        }
        if meetsEndToEnd == false, let crossed = try crossingLoop(pieces, tolerance: tolerance) {
            pieces = crossed
        }
        var loop = pieces.removeFirst()
        while pieces.isEmpty == false {
            let end = try ends(loop).1
            guard let index = try pieces.firstIndex(where: { piece in
                let (start, finish) = try ends(piece)
                return (start - end).length <= tolerance.distance || (finish - end).length <= tolerance.distance
            }) else {
                throw failure("A curve patch's curves do not meet end to end.")
            }
            let piece = pieces.remove(at: index)
            if (try ends(piece).0 - end).length <= tolerance.distance {
                loop += piece
            } else {
                loop += try piece.reversed().map { try $0.reversed(tolerance: tolerance) }
            }
        }
        let (start, end) = try ends(loop)
        guard (start - end).length <= tolerance.distance else {
            throw failure("A curve patch's curves do not close into a loop.")
        }
        // A planar loop spans its exact trimmed plane.
        if let geometry = try DefaultPlanarSurfaceResolver().plane(forControlPoints: loop.lazy.map(\.controlPoints).joined(),
                                                                   tolerance: tolerance) {
            let plane = Surface3D.plane(Plane3D(origin: geometry.origin, normal: geometry.normal))
            let edges = try loop.enumerated().map { index, curve -> BRepSewingEdge in
                guard case let .closed(lower, upper) = curve.domain else { throw failure("A curve patch's span is unbounded.") }
                let pcurve = BSplineCurve2D(degree: curve.degree, knots: curve.knots, controlPoints: try curve.controlPoints.map { point in
                    let projection = try plane.parameterProjection(of: point, tolerance: tolerance)
                    return Point2D(x: projection.u, y: projection.v)
                }, weights: curve.weights)
                return BRepSewingEdge(
                    stableID: "curvePatch:boundary:\(index)", curve: .bSpline(curve), startParameter: lower, endParameter: upper,
                    startPoint: try curve.point(at: lower, tolerance: tolerance), endPoint: try curve.point(at: upper, tolerance: tolerance),
                    surfaceParameterCurve: .bSpline(pcurve)
                )
            }
            let sewn = try sewer.sew(BRepSewingRequest(
                featureID: feature.id, bodyKind: .sheet,
                shells: [BRepSewingShell(stableID: "curvePatch:shell", patches: [BRepSewingFacePatch(
                    stableID: "curvePatch:face", surface: plane, orientation: .forward,
                    loops: [BRepSewingLoop(stableID: "curvePatch:boundary", role: .outer, edges: edges)]
                )])]
            ), tolerance: tolerance)
            return EvaluationResult(brep: try BRepModelCombiner().combined([context.brep, sewn.brep]),
                                    subshapes: sewn.subshapes, lineage: sewn.lineage)
        }
        // A loop with more than four corners (where it turns sharply) is filled smoothly; one
        // with at most four is the exact Coons patch of its four sides.
        var corners = 0
        for (span, next) in zip(loop, loop.dropFirst() + [loop[0]]) {
            guard case let .closed(_, upper) = span.domain, case let .closed(lower, _) = next.domain else { continue }
            let out = try span.differentialGeometry(at: upper, tolerance: tolerance).firstDerivative
            let into = try next.differentialGeometry(at: lower, tolerance: tolerance).firstDerivative
            if out.cross(into).length > sin(1e-6) * out.length * into.length || out.dot(into) <= 0 { corners += 1 }
        }
        if corners > 4 {
            guard let loopFiller else {
                throw KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: feature.id, tolerance: tolerance,
                                  message: "A loop with more than four corners needs a loop filler to span smoothly.")
            }
            return try loopFiller.fill(loop: loop, feature: feature, context: context)
        }
        let sides = try surfaceFill.fourSides(from: loop, tolerance: tolerance)
        let surface = try ExactCoonsBSplineSurfaceBuilder().build(
            vMinimumBoundary: sides[0], vMaximumBoundary: try sides[2].reversed(tolerance: tolerance),
            uMinimumBoundary: try sides[3].reversed(tolerance: tolerance), uMaximumBoundary: sides[1],
            tolerance: tolerance
        )
        return try sheetEvaluator.evaluateValidated(
            feature: FeatureNode(id: feature.id, name: feature.name,
                                 operation: .bSplineSurface(BSplineSurfaceFeature(surface: surface, material: nil)),
                                 outputs: feature.outputs, isSuppressed: feature.isSuppressed),
            context: context
        ).result
    }

    /// The curves cut between their crossings, when each crosses exactly two others and they
    /// close a cycle; nil otherwise. A crossing is where a point of one curve and its nearest point
    /// on the other converge to the same point (alternating projections from sampled seeds).
    private func crossingLoop(_ curves: [[BSplineCurve3D]], tolerance: ModelingTolerance) throws -> [[BSplineCurve3D]]? {
        struct Hit { let other: Int; let span: Int; let parameter: Double; let point: Point3D }
        func bounds(_ span: BSplineCurve3D) -> (Double, Double)? {
            if case let .closed(lower, upper) = span.domain { return (lower, upper) }
            return nil
        }
        /// The point of the spans nearest `point`: the best of sixteen samples per span, then Newton
        /// steps on the squared distance, kept within the span.
        func nearest(on spans: [BSplineCurve3D], to point: Point3D) throws -> (span: Int, parameter: Double, point: Point3D) {
            var best: (span: Int, parameter: Double, point: Point3D, distance: Double)?
            for (index, span) in spans.enumerated() {
                guard let (lower, upper) = bounds(span) else { continue }
                var t = lower
                var closest = Double.infinity
                for step in 0...16 {
                    let candidate = lower + (upper - lower) * Double(step) / 16
                    let distance = (try span.point(at: candidate, tolerance: tolerance) - point).length
                    if distance < closest { (closest, t) = (distance, candidate) }
                }
                for _ in 0..<30 {
                    let geometry = try span.differentialGeometry(at: t, tolerance: tolerance)
                    let offset = geometry.position - point
                    let slope = offset.dot(geometry.firstDerivative)
                    let curvature = geometry.firstDerivative.dot(geometry.firstDerivative) + offset.dot(geometry.secondDerivative)
                    guard curvature > 0 else { break }
                    let next = min(max(t - slope / curvature, lower), upper)
                    if abs(next - t) <= 1e-15 * max(1, abs(t)) { t = next; break }
                    t = next
                }
                let onSpan = try span.point(at: t, tolerance: tolerance)
                let distance = (onSpan - point).length
                if best == nil || distance < best!.distance { best = (index, t, onSpan, distance) }
            }
            guard let best else { throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "A patch curve has no span.") }
            return (best.span, best.parameter, best.point)
        }
        var hits: [[Hit]] = curves.map { _ in [] }
        for a in curves.indices {
            for b in curves.indices where b > a {
                var found: [(spanA: Int, ta: Double, spanB: Int, tb: Double, point: Point3D)] = []
                for (spanIndex, span) in curves[a].enumerated() {
                    guard let (lower, upper) = bounds(span) else { continue }
                    for step in 0...32 {
                        var t = lower + (upper - lower) * Double(step) / 32
                        var spanA = spanIndex
                        var onA = try Curve3D.bSpline(curves[a][spanA]).point(at: t, tolerance: tolerance)
                        var onB = try nearest(on: curves[b], to: onA)
                        for _ in 0..<60 {
                            let back = try nearest(on: curves[a], to: onB.point)
                            (spanA, t, onA) = (back.span, back.parameter, back.point)
                            onB = try nearest(on: curves[b], to: onA)
                            if (onA - onB.point).length <= tolerance.distance * 1e-3 { break }
                        }
                        guard (onA - onB.point).length <= tolerance.distance * 1e-2,
                              found.contains(where: { ($0.point - onA).length <= tolerance.distance }) == false else { continue }
                        found.append((spanA, t, onB.span, onB.parameter, Point3D.origin + ((onA - .origin) + (onB.point - .origin)) * 0.5))
                    }
                }
                guard found.count <= 1 else { return nil }
                if let crossing = found.first {
                    hits[a].append(Hit(other: b, span: crossing.spanA, parameter: crossing.ta, point: crossing.point))
                    hits[b].append(Hit(other: a, span: crossing.spanB, parameter: crossing.tb, point: crossing.point))
                }
            }
        }
        guard hits.allSatisfy({ $0.count == 2 }) else { return nil }
        // Each curve between its two crossings, both ends at the crossing points.
        return try curves.indices.map { index -> [BSplineCurve3D] in
            let ordered = hits[index].sorted { ($0.span, $0.parameter) < ($1.span, $1.parameter) }
            let (first, last) = (ordered[0], ordered[1])
            var result: [BSplineCurve3D] = []
            for spanIndex in first.span...last.span {
                let span = curves[index][spanIndex]
                guard let (lower, upper) = bounds(span) else { continue }
                let from = spanIndex == first.span ? first.parameter : lower
                let to = spanIndex == last.span ? last.parameter : upper
                guard to - from > tolerance.relative * max(1, abs(upper - lower)) else { continue }
                var piece = try span.trimmed(from: from, to: to, tolerance: tolerance)
                // The ends exactly at the crossings, so neighbouring pieces meet.
                if spanIndex == first.span { piece.controlPoints[0] = first.point }
                if spanIndex == last.span { piece.controlPoints[piece.controlPoints.count - 1] = last.point }
                result.append(piece)
            }
            guard result.isEmpty == false else {
                throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "A patch curve has nothing between its crossings.")
            }
            return result
        }
    }
}
