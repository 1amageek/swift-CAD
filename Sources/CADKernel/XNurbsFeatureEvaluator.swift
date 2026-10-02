import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// XNURBS: with Quad sided, Square's untrimmed sheet over its two to four boundaries (Degree 3,
/// the Quality's spans, its flatness and boundary flow, guides as weighted points); otherwise its
/// boundary curves joined end to end into a closed loop and `XNurbsSurfaceFitter`'s sheet over the
/// loop's mean plane, trimmed by the loop: one face whose edges are the sheet along each curve's
/// trimming curve (fitted within a quarter of the modeling distance), its deviation from the
/// boundary within the feature's tolerances when it satisfies them.
struct XNurbsFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let sewer: any BRepSewing
    private let surfaceEvaluator = BSplineSurfaceFeatureEvaluator()

    init(sewer: any BRepSewing) {
        self.sewer = sewer
    }

    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try build(feature: feature, context: context)
        }
    }

    private func build(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        let tolerance = context.tolerance
        guard case let .xnurbs(xnurbs) = feature.operation else {
            throw failure(.invalidInput, feature.id, tolerance, "The XNURBS evaluator received another feature.")
        }
        try xnurbs.validate()
        let curves = try SquareSurfaceFeatureEvaluator.sideCurves(of: xnurbs.boundaries, curves: context.curves, tolerance: tolerance,
                                                                  featureID: feature.id)
        let guides = try SquareSurfaceFeatureEvaluator.sideCurves(of: xnurbs.guides.map { SquareSide(curve: $0) }, curves: context.curves,
                                                                  tolerance: tolerance, featureID: feature.id)
        if xnurbs.quadSided {
            return try quadSided(xnurbs, curves: curves, guides: guides, feature: feature, context: context)
        }
        // The boundary joined end to end into a loop, each curve turned to run along it.
        var loop: [(curve: BSplineCurve3D, index: Int)] = [(curves[0], 0)]
        var remaining = Array(curves.indices.dropFirst())
        while remaining.isEmpty == false {
            let end = try ends(loop[loop.count - 1].curve, tolerance).1
            guard let position = try remaining.firstIndex(where: { index in
                let (a, b) = try ends(curves[index], tolerance)
                return (a - end).length <= tolerance.distance || (b - end).length <= tolerance.distance
            }) else {
                throw failure(.invalidInput, feature.id, tolerance, "An XNURBS's boundary curves do not meet end to end.")
            }
            let index = remaining.remove(at: position)
            let forward = (try ends(curves[index], tolerance).0 - end).length <= tolerance.distance
            loop.append((forward ? curves[index] : try curves[index].reversed(tolerance: tolerance), index))
        }
        guard (try ends(loop[loop.count - 1].curve, tolerance).1 - ends(loop[0].curve, tolerance).0).length <= tolerance.distance else {
            throw failure(.invalidInput, feature.id, tolerance, "An XNURBS's boundary does not close; Quad sided spans an open frame.")
        }
        let centroid = try loop.map { try ends($0.curve, tolerance).0 }.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * (1 / Double(loop.count))
        let boundaries = try loop.map { entry -> XNurbsSurfaceFitter.Boundary in
            guard let continuity = xnurbs.boundaries[entry.index].continuity else { return .init(curve: entry.curve) }
            guard case let .closed(lower, upper) = entry.curve.domain else {
                throw failure(.invalidInput, feature.id, tolerance, "An XNURBS boundary curve is unbounded.")
            }
            let start = try entry.curve.differentialGeometry(at: lower, tolerance: tolerance)
            let middle = try entry.curve.differentialGeometry(at: 0.5 * (lower + upper), tolerance: tolerance).position
            return .init(curve: entry.curve, support: try ExactEdgeContinuitySupportResolver().support(
                for: continuity, point: start.position, derivative: start.firstDerivative,
                toward: (Point3D.origin + centroid) - middle, context: context, featureID: feature.id
            ))
        }
        let fit = try XNurbsSurfaceFitter(tolerance: tolerance).fit(
            boundaries: boundaries, guides: guides, flatness: xnurbs.flatness, spans: xnurbs.quality.spans,
            satisfying: xnurbs.satisfiesTolerances ? (xnurbs.positionTolerance, xnurbs.angleTolerance) : nil, featureID: feature.id
        )
        // One face trimmed by the loop, each edge the sheet along its curve's trimming curve.
        let surface = Surface3D.bSpline(fit.surface)
        let curveFitter = try SpatialCurveFitter(deviation: tolerance.distance / 4)
        let edges = try zip(loop.indices, fit.pcurves).map { position, pcurve -> BRepSewingEdge in
            guard case let .closed(lower, upper) = pcurve.domain else {
                throw failure(.invalidInput, feature.id, tolerance, "An XNURBS trimming curve is unbounded.")
            }
            let along = { (t: Double) throws -> Point3D in
                let uv = try pcurve.point(at: t, tolerance: tolerance)
                return try surface.point(u: min(1, max(0, uv.x)), v: min(1, max(0, uv.y)), tolerance: tolerance)
            }
            let curve = try curveFitter.fitBSpline(breakpoints: [lower, upper], tolerance: tolerance, point: along).curve
            return BRepSewingEdge(
                stableID: "xnurbs:boundary:\(position)", curve: .bSpline(curve), startParameter: lower, endParameter: upper,
                startPoint: try along(lower), endPoint: try along(upper), surfaceParameterCurve: .bSpline(pcurve)
            )
        }
        let sewn = try sewer.sew(BRepSewingRequest(
            featureID: feature.id, bodyKind: .sheet,
            shells: [BRepSewingShell(stableID: "xnurbs:shell", patches: [BRepSewingFacePatch(
                stableID: "xnurbs:face", surface: surface, orientation: .forward,
                loops: [BRepSewingLoop(stableID: "xnurbs:boundary", role: .outer, edges: edges)]
            )])]
        ), tolerance: tolerance)
        return EvaluationResult(brep: try BRepModelCombiner().combined([context.brep, sewn.brep]), subshapes: sewn.subshapes, lineage: sewn.lineage)
    }

    /// Square's sheet over the boundaries, with the XNURBS's quality, flatness, flow and guides.
    private func quadSided(_ xnurbs: XNurbsFeature, curves: [BSplineCurve3D], guides: [BSplineCurve3D], feature: FeatureNode,
                           context: EvaluationContext) throws -> EvaluationResult {
        let tolerance = context.tolerance
        let frame = try SquareFrameBuilder(tolerance: tolerance).frame(of: curves, featureID: feature.id)
        let continuities = frame.map { side in side.given.flatMap { xnurbs.boundaries[$0].continuity } }
        let (exact, rotation) = try SquareSurfaceFeatureEvaluator.exactSheet(frame: frame, continuities: continuities, context: context,
                                                                             featureID: feature.id)
        let boundaries = (0..<4).map { boundary -> SquareSurfaceFitter.Boundary in
            let side = frame[(boundary + rotation) % 4]
            guard side.given != nil else { return .init(constraint: .none, flows: false) }
            switch continuities[(boundary + rotation) % 4]?.order {
            case nil: return .init(constraint: .hard(order: 0), flows: true)
            case .tangent?: return .init(constraint: .hard(order: 1), flows: false)
            case .curvature?: return .init(constraint: .hard(order: 2), flows: false)
            }
        }
        let guidePoints = try guides.flatMap { guide -> [Point3D] in
            guard case let .closed(lower, upper) = guide.domain else {
                throw failure(.invalidInput, feature.id, tolerance, "An XNURBS guide is unbounded.")
            }
            return try (0...32).map { try Curve3D.bSpline(guide).point(at: lower + (upper - lower) * Double($0) / 32, tolerance: tolerance) }
        }
        let options = SquareFitOptions(uSpans: xnurbs.quality.spans, vSpans: xnurbs.quality.spans, flatness: xnurbs.flatness,
                                       weight: 1, boundaryFlow: xnurbs.boundaryFlow)
        let surface = try SquareSurfaceFitter(tolerance: tolerance).fit(exact: exact, boundaries: boundaries, options: options,
                                                                        guides: guidePoints, featureID: feature.id)
        return try surfaceEvaluator.evaluateValidated(
            feature: FeatureNode(id: feature.id, name: feature.name,
                                 operation: .bSplineSurface(BSplineSurfaceFeature(surface: surface, material: nil)),
                                 outputs: feature.outputs, isSuppressed: feature.isSuppressed),
            context: context
        ).result
    }

    private func ends(_ curve: BSplineCurve3D, _ tolerance: ModelingTolerance) throws -> (Point3D, Point3D) {
        guard case let .closed(lower, upper) = curve.domain else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "An XNURBS curve is unbounded.")
        }
        return (try Curve3D.bSpline(curve).point(at: lower, tolerance: tolerance), try Curve3D.bSpline(curve).point(at: upper, tolerance: tolerance))
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
