import CADCore
import CADGeometry
import CADIR

/// Square: its four side curves joined end to end into a frame, and the sheet spanning it. With
/// every side at G0 the sheet is the exact Coons patch of the frame; with continuity along one side
/// or two opposite sides it is `ExactHermiteCoonsSurfaceBuilder`'s surface, tangent or curvature
/// continuous with the planar faces beside those sides' edges.
public struct SquareSurfaceFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let surfaceEvaluator = BSplineSurfaceFeatureEvaluator()

    public init() {}

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
        guard case let .squareSurface(square) = feature.operation else {
            throw KernelError(phase: .validation, code: .invalidInput, featureID: feature.id, tolerance: tolerance,
                              message: "SquareSurfaceFeatureEvaluator requires a Square feature.")
        }
        try square.validate()
        let curves = try square.sides.map { side -> BSplineCurve3D in
            let evaluated = try ResolvedModelingSection.resolveCurve(side.curve, from: context.curves[side.curve.featureID], tolerance: tolerance)
            guard evaluated.isClosed == false else {
                throw failure(.invalidInput, "A Square's side is an open curve.", feature.id, tolerance)
            }
            let spans = try ExactBSplineCurveSpanBuilder(tolerance: tolerance).sectionSpans(from: evaluated)
            return spans.count == 1 ? spans[0].curve
                : try ExactCompositeBSplineCurveBuilder().build(spans: spans.map(\.curve), tolerance: tolerance)
        }
        // The frame: from the first side, each next side the one starting (or, turned, ending)
        // where the last one ends.
        func ends(_ curve: BSplineCurve3D) throws -> (Point3D, Point3D) {
            guard case let .closed(lower, upper) = curve.domain else {
                throw failure(.invalidInput, "A Square's side has an unbounded domain.", feature.id, tolerance)
            }
            return (try Curve3D.bSpline(curve).point(at: lower, tolerance: tolerance), try Curve3D.bSpline(curve).point(at: upper, tolerance: tolerance))
        }
        var frame: [(curve: BSplineCurve3D, side: Int)] = [(curves[0], 0)]
        var remaining = [1, 2, 3]
        while frame.count < 4 {
            let end = try ends(frame[frame.count - 1].curve).1
            var next: (BSplineCurve3D, Int)?
            for index in remaining {
                let (start, finish) = try ends(curves[index])
                if (start - end).length <= tolerance.distance { next = (curves[index], index); break }
                if (finish - end).length <= tolerance.distance { next = (try curves[index].reversed(tolerance: tolerance), index); break }
            }
            guard let next else { throw failure(.invalidInput, "A Square's sides do not meet end to end.", feature.id, tolerance) }
            frame.append(next)
            remaining.removeAll { $0 == next.1 }
        }
        guard (try ends(frame[3].curve).1 - ends(frame[0].curve).0).length <= tolerance.distance else {
            throw failure(.invalidInput, "A Square's sides do not close into a frame.", feature.id, tolerance)
        }
        let continuous = frame.indices.filter { square.sides[frame[$0].side].continuity != nil }
        let surface: BSplineSurface3D
        if continuous.isEmpty {
            surface = try ExactCoonsBSplineSurfaceBuilder().build(
                vMinimumBoundary: frame[0].curve, vMaximumBoundary: try frame[2].curve.reversed(tolerance: tolerance),
                uMinimumBoundary: try frame[3].curve.reversed(tolerance: tolerance), uMaximumBoundary: frame[1].curve,
                tolerance: tolerance
            )
        } else {
            guard Set(continuous).isSubset(of: [0, 2]) || Set(continuous).isSubset(of: [1, 3]) else {
                // Continuous along neighbouring sides: the four-sided Boolean sum with shared twists.
                let bottom = frame[0].curve, right = frame[1].curve
                let top = try frame[2].curve.reversed(tolerance: tolerance), left = try frame[3].curve.reversed(tolerance: tolerance)
                let center = try [bottom, right, top, left].map { try ends($0).0 }.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * 0.25
                let curves = try [bottom, top, left, right].map(normalized)
                let supports = try zip(curves, [frame[0].side, frame[2].side, frame[3].side, frame[1].side]).map { curve, side -> ExactEdgeContinuitySupport? in
                    guard let continuity = square.sides[side].continuity else { return nil }
                    let start = try curve.differentialGeometry(at: 0, tolerance: tolerance)
                    let middle = try curve.differentialGeometry(at: 0.5, tolerance: tolerance).position
                    return try ExactEdgeContinuitySupportResolver().support(
                        for: continuity, point: start.position, derivative: start.firstDerivative,
                        toward: (Point3D.origin + center) - middle, context: context, featureID: feature.id
                    )
                }
                let spanning = try ExactHermiteCoonsSurfaceBuilder(tolerance: tolerance).buildAllSides(
                    bottom: curves[0], top: curves[1], left: curves[2], right: curves[3],
                    bottomSupport: supports[0], topSupport: supports[1], leftSupport: supports[2], rightSupport: supports[3],
                    featureID: feature.id
                )
                return try surfaceEvaluator.evaluateValidated(
                    feature: FeatureNode(id: feature.id, name: feature.name,
                                         operation: .bSplineSurface(BSplineSurfaceFeature(surface: spanning, material: nil)),
                                         outputs: feature.outputs, isSuppressed: feature.isSuppressed),
                    context: context
                ).result
            }
            // The continuous sides run along u at v = 0 and v = 1.
            let turned = Set(continuous).isSubset(of: [1, 3]) ? Array(frame[1...] + frame[..<1]) : frame
            let bottom = turned[0].curve, right = turned[1].curve
            let top = try turned[2].curve.reversed(tolerance: tolerance), left = try turned[3].curve.reversed(tolerance: tolerance)
            let center = try [bottom, right, top, left].map { try ends($0).0 }.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * 0.25
            func plane(_ curve: BSplineCurve3D, side: Int) throws -> ExactEdgeContinuitySupport? {
                guard let continuity = square.sides[side].continuity else { return nil }
                let start = try curve.differentialGeometry(at: 0, tolerance: tolerance)
                let middle = try curve.differentialGeometry(at: 0.5, tolerance: tolerance).position
                return try ExactEdgeContinuitySupportResolver().support(
                    for: continuity, point: start.position, derivative: start.firstDerivative,
                    toward: (Point3D.origin + center) - middle, context: context, featureID: feature.id
                )
            }
            let normalizedBottom = try normalized(bottom), normalizedTop = try normalized(top)
            surface = try ExactHermiteCoonsSurfaceBuilder(tolerance: tolerance).build(
                bottom: normalizedBottom, top: normalizedTop, left: try normalized(left), right: try normalized(right),
                bottomPlane: try plane(normalizedBottom, side: turned[0].side),
                topPlane: try plane(normalizedTop, side: turned[2].side),
                featureID: feature.id
            )
        }
        return try surfaceEvaluator.evaluateValidated(
            feature: FeatureNode(id: feature.id, name: feature.name,
                                 operation: .bSplineSurface(BSplineSurfaceFeature(surface: surface, material: nil)),
                                 outputs: feature.outputs, isSuppressed: feature.isSuppressed),
            context: context
        ).result
    }

    /// `curve` reparameterized over [0, 1].
    private func normalized(_ curve: BSplineCurve3D) throws -> BSplineCurve3D {
        guard let lower = curve.knots.first, let upper = curve.knots.last, upper > lower else {
            throw FeatureEvaluationError.invalidGraph("A Square's side has a degenerate knot vector.")
        }
        return BSplineCurve3D(degree: curve.degree, knots: curve.knots.map { ($0 - lower) / (upper - lower) },
                              controlPoints: curve.controlPoints, weights: curve.weights)
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ featureID: FeatureID, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
