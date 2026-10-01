import CADCore
import CADGeometry
import CADIR

/// Patch from closed curves: the curves joined end to end into one closed loop (or one closed
/// curve) and the sheet spanning it — the exact trimmed plane of a planar loop, or the exact Coons
/// patch of a loop that groups into four sides.
public struct CurvePatchFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let sewer: any BRepSewing
    private let surfaceFill: SurfaceFillFeatureEvaluator
    private let sheetEvaluator = BSplineSurfaceFeatureEvaluator()

    public init(sewer: any BRepSewing) {
        self.sewer = sewer
        surfaceFill = SurfaceFillFeatureEvaluator(sewer: sewer)
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
        // Otherwise the loop's four sides span the exact Coons patch.
        // FIXME(INCOMPLETE_IMPLEMENTATION): a non-planar loop is spanned only through four sides;
        // an N-sided constrained fill (XNURBS's solver) is not built, so a loop that does not group
        // into four sides is refused by the side grouping. Production path:
        // CurvePatchFeatureEvaluator for every non-planar curve patch. Complete only when N-sided
        // loops are spanned with stated precision, verified by a five-sided non-planar patch.
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
}
