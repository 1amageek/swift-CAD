import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Imprints a face's parameter lines (`IsoparamFeature`) through `BRepFaceImprinter`: each line
/// holds `direction`'s parameter at its fraction of the face's extent, reaches a little past the
/// face on either side within the surface's own domain, and is clipped to the face
/// (`BRepFaceCurveClipper`). Subdividing a B-spline surface first inserts each line's knot up to
/// the surface's degree, which keeps its shape and parameters, so the pieces share that row of
/// control points.
struct IsoparamFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let subshapeResolver: any StableSubshapeResolving

    init(subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()) {
        self.subshapeResolver = subshapeResolver
    }

    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try isoparam(feature: feature, context: context)
        }
    }

    private func isoparam(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .isoparam(isoparam) = feature.operation else {
            throw failure(.invalidInput, feature.id, context, "Isoparam evaluator requires an isoparam feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try isoparam.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let tolerance = context.tolerance
        let bodyID = try context.bodyID(generatedBy: isoparam.target.featureID)
        guard case let .face(faceID) = try subshapeResolver.topologyReference(
            for: isoparam.face, model: context.brep, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance
        ), let face = context.brep.faces[faceID], let original = context.brep.geometry.surfaces[face.surfaceID] else {
            throw failure(.missingReference, feature.id, context, "Isoparam's face is not a face of its body.")
        }
        let subshapes = context.subshapes.entries
        let bounds = try BRepFaceCurveClipper.parameterBounds(of: faceID, model: context.brep, sourceSubshapes: subshapes, tolerance: tolerance)
        let across = isoparam.direction == .u ? bounds.u : bounds.v
        let values = isoparam.fractions.sorted().map { across.lowerBound + $0 * (across.upperBound - across.lowerBound) }
        var imprinting = context
        var surface = original
        if isoparam.subdividesControlNet {
            guard case .bSpline(var spline) = original else {
                throw failure(.invalidInput, feature.id, context, "Subdivide splits a control net; this face's surface has none.")
            }
            for value in values {
                spline = try knotted(spline, direction: isoparam.direction, at: value, tolerance: tolerance)
            }
            surface = .bSpline(spline)
            imprinting.brep.geometry.surfaces[face.surfaceID] = surface
        }
        let along = isoparam.direction == .u ? bounds.v : bounds.u
        let span = try reach(of: along, within: isoparam.direction == .u ? surface.vDomain : surface.uDomain, tolerance: tolerance)
        var curves: [BRepFaceImprinter.Curve] = []
        let faceParents = context.subshapeIDs(for: .face(faceID))
        for (index, value) in values.enumerated() {
            let line: SurfaceParameterCurve = isoparam.direction == .u
                ? .constantU(u: value, vStart: span.lowerBound, vEnd: span.upperBound)
                : .constantV(v: value, uStart: span.lowerBound, uEnd: span.upperBound)
            let pieces = try BRepFaceCurveClipper().clip(
                line, to: faceID, stableID: "isoparam:\(index)", parentSubshapeIDs: faceParents,
                model: imprinting.brep, sourceSubshapes: subshapes, tolerance: tolerance
            )
            curves += pieces.map { BRepFaceImprinter.Curve(faceID: faceID, edge: $0) }
        }
        guard curves.isEmpty == false else {
            throw failure(.invalidInput, feature.id, context, "No Isoparam line crosses the face.")
        }
        return try BRepFaceImprinter().imprint(curves, on: bodyID, featureID: feature.id, context: imprinting)
    }

    /// The face's extent along the lines, reaching a twentieth past each end so the lines cross
    /// the face's boundary, but never outside a bounded domain nor around a periodic one twice.
    private func reach(of extent: ClosedRange<Double>, within domain: ParameterDomain, tolerance: ModelingTolerance) throws -> ClosedRange<Double> {
        let margin = (extent.upperBound - extent.lowerBound) * 0.05
        switch domain {
        case .unbounded:
            return (extent.lowerBound - margin)...(extent.upperBound + margin)
        case let .closed(lower, upper):
            return max(lower, extent.lowerBound - margin)...min(upper, extent.upperBound + margin)
        case let .periodic(period):
            let length = extent.upperBound - extent.lowerBound
            guard length < period - tolerance.angle else { return extent }
            let reach = min(margin, (period - length) / 2)
            return (extent.lowerBound - reach)...(extent.upperBound + reach)
        }
    }

    /// `spline` with the knot `value` in `direction` repeated as many times as its degree there.
    private func knotted(_ spline: BSplineSurface3D, direction: SurfaceParameterDirection, at value: Double, tolerance: ModelingTolerance) throws -> BSplineSurface3D {
        var result = spline
        let degree = direction == .u ? spline.uDegree : spline.vDegree
        func multiplicity() -> Int {
            (direction == .u ? result.uKnots : result.vKnots).filter { abs($0 - value) <= tolerance.angle }.count
        }
        while multiplicity() < degree {
            result = try result.insertingKnot(direction: direction, value: value, tolerance: tolerance)
        }
        return result
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ context: EvaluationContext, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: context.tolerance, message: message)
    }
}
