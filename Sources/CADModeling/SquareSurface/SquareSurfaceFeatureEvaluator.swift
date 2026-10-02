import CADCore
import CADGeometry
import CADIR

/// Square: its side curves completed into a four-sided frame (`SquareFrameBuilder`), the exact
/// sheet spanning it — the Coons patch, or `ExactHermiteCoonsSurfaceBuilder`'s sheet tangent or
/// curvature continuous with the faces beside its continuous sides — and that sheet refitted into
/// the requested Degree and Spans with its hard rows kept (`SquareSurfaceFitter`).
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
        let curves = try Self.sideCurves(of: square, curves: context.curves, tolerance: tolerance, featureID: feature.id)
        let frame = try SquareFrameBuilder(tolerance: tolerance).frame(of: curves, featureID: feature.id)
        // A Free side frames the exact sheet as a curve but takes no continuity.
        let continuities = frame.map { side in side.given.flatMap { square.sides[$0].isFree ? nil : square.sides[$0].continuity } }
        let (exact, rotation) = try exactSheet(frame: frame, continuities: continuities, context: context, featureID: feature.id)
        let boundaries = (0..<4).map { boundary -> SquareSurfaceFitter.Boundary in
            let side = frame[(boundary + rotation) % 4]
            guard let given = side.given else { return .init(constraint: .none, flows: false) }
            if square.sides[given].isFree { return .init(constraint: .loose, flows: true) }
            switch square.sides[given].continuity?.order {
            case nil: return .init(constraint: .hard(order: 0), flows: true)
            case .tangent?: return .init(constraint: .hard(order: 1), flows: false)
            case .curvature?: return .init(constraint: .hard(order: 2), flows: false)
            }
        }
        let surface = try SquareSurfaceFitter(tolerance: tolerance).fit(exact: exact, boundaries: boundaries, options: square.options,
                                                                        featureID: feature.id)
        return try surfaceEvaluator.evaluateValidated(
            feature: FeatureNode(id: feature.id, name: feature.name,
                                 operation: .bSplineSurface(BSplineSurfaceFeature(surface: surface, material: nil)),
                                 outputs: feature.outputs, isSuppressed: feature.isSuppressed),
            context: context
        ).result
    }

    /// The exact sheet spanning the frame, and the rotation r putting frame side (k + r) mod 4 on
    /// its boundary k (v = 0, u = 1, v = 1, u = 0). With every side at G0 it is the exact Coons
    /// patch; with continuity along one side or two opposite ones those run along u; along
    /// neighbouring sides it is the four-sided Boolean sum with shared twists.
    private func exactSheet(frame: [SquareFrameBuilder.Side], continuities: [SurfaceEdgeContinuity?],
                            context: EvaluationContext, featureID: FeatureID) throws -> (BSplineSurface3D, Int) {
        let tolerance = context.tolerance
        func ends(_ curve: BSplineCurve3D) throws -> (Point3D, Point3D) {
            guard case let .closed(lower, upper) = curve.domain else {
                throw failure(.invalidInput, "A Square's side has an unbounded domain.", featureID, tolerance)
            }
            return (try Curve3D.bSpline(curve).point(at: lower, tolerance: tolerance), try Curve3D.bSpline(curve).point(at: upper, tolerance: tolerance))
        }
        let continuous = frame.indices.filter { continuities[$0] != nil }
        if continuous.isEmpty {
            return (try ExactCoonsBSplineSurfaceBuilder().build(
                vMinimumBoundary: frame[0].curve, vMaximumBoundary: try frame[2].curve.reversed(tolerance: tolerance),
                uMinimumBoundary: try frame[3].curve.reversed(tolerance: tolerance), uMaximumBoundary: frame[1].curve,
                tolerance: tolerance
            ), 0)
        }
        func support(_ curve: BSplineCurve3D, _ continuity: SurfaceEdgeContinuity?, center: Vector3D) throws -> ExactEdgeContinuitySupport? {
            guard let continuity else { return nil }
            let start = try curve.differentialGeometry(at: 0, tolerance: tolerance)
            let middle = try curve.differentialGeometry(at: 0.5, tolerance: tolerance).position
            return try ExactEdgeContinuitySupportResolver().support(
                for: continuity, point: start.position, derivative: start.firstDerivative,
                toward: (Point3D.origin + center) - middle, context: context, featureID: featureID
            )
        }
        guard Set(continuous).isSubset(of: [0, 2]) || Set(continuous).isSubset(of: [1, 3]) else {
            // Continuous along neighbouring sides: the four-sided Boolean sum with shared twists.
            let bottom = frame[0].curve, right = frame[1].curve
            let top = try frame[2].curve.reversed(tolerance: tolerance), left = try frame[3].curve.reversed(tolerance: tolerance)
            let center = try [bottom, right, top, left].map { try ends($0).0 }.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * 0.25
            let curves = try [bottom, top, left, right].map(normalized)
            let supports = try zip(curves, [continuities[0], continuities[2], continuities[3], continuities[1]]).map {
                try support($0, $1, center: center)
            }
            return (try ExactHermiteCoonsSurfaceBuilder(tolerance: tolerance).buildAllSides(
                bottom: curves[0], top: curves[1], left: curves[2], right: curves[3],
                bottomSupport: supports[0], topSupport: supports[1], leftSupport: supports[2], rightSupport: supports[3],
                featureID: featureID
            ), 0)
        }
        // The continuous sides run along u at v = 0 and v = 1.
        let rotation = Set(continuous).isSubset(of: [1, 3]) ? 1 : 0
        let turned = (0..<4).map { frame[($0 + rotation) % 4] }
        let turnedContinuities = (0..<4).map { continuities[($0 + rotation) % 4] }
        let bottom = turned[0].curve, right = turned[1].curve
        let top = try turned[2].curve.reversed(tolerance: tolerance), left = try turned[3].curve.reversed(tolerance: tolerance)
        let center = try [bottom, right, top, left].map { try ends($0).0 }.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * 0.25
        let normalizedBottom = try normalized(bottom), normalizedTop = try normalized(top)
        return (try ExactHermiteCoonsSurfaceBuilder(tolerance: tolerance).build(
            bottom: normalizedBottom, top: normalizedTop, left: try normalized(left), right: try normalized(right),
            bottomPlane: try support(normalizedBottom, turnedContinuities[0], center: center),
            topPlane: try support(normalizedTop, turnedContinuities[2], center: center),
            featureID: featureID
        ), rotation)
    }

    /// The Square's given side curves, in its order, each one exact B-spline.
    package static func sideCurves(of square: SquareSurfaceFeature, curves: [FeatureID: [EvaluatedCurve]],
                                   tolerance: ModelingTolerance, featureID: FeatureID) throws -> [BSplineCurve3D] {
        try square.sides.map { side -> BSplineCurve3D in
            let evaluated = try ResolvedModelingSection.resolveCurve(side.curve, from: curves[side.curve.featureID], tolerance: tolerance)
            guard evaluated.isClosed == false else {
                throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                                  message: "A Square's side is an open curve.")
            }
            let spans = try ExactBSplineCurveSpanBuilder(tolerance: tolerance).sectionSpans(from: evaluated)
            return spans.count == 1 ? spans[0].curve
                : try ExactCompositeBSplineCurveBuilder().build(spans: spans.map(\.curve), tolerance: tolerance)
        }
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
