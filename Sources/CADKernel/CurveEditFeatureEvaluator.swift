import CADCore
import CADIR

public struct CurveEditFeatureEvaluator: FeatureEvaluating {
    public init() {}

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .curveEdit(curveEdit) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation("CurveEditFeatureEvaluator requires a curve edit feature.")
        }
        try curveEdit.validate(tolerance: context.tolerance)

        var curve = try exactBSpline(source: curveEdit.source, context: context)
        for edit in curveEdit.edits {
            try apply(edit, to: &curve)
        }
        try curve.validate(tolerance: context.tolerance)

        let generatedCurve = try evaluatedCurve(
            featureID: feature.id,
            curve: curve,
            sampleCount: curveEdit.sampleCount,
            tolerance: context.tolerance
        )
        return EvaluationResult(
            brep: context.brep,
            generatedNames: [:],
            generatedCurves: [generatedCurve]
        )
    }

    private func exactBSpline(
        source: CurveOutputReference,
        context: EvaluationContext
    ) throws -> BSplineCurve3D {
        try source.validate()
        guard let curves = context.curves[source.featureID] else {
            throw FeatureEvaluationError.missingInput("Curve edit source feature could not be resolved.")
        }
        guard source.curveIndex < curves.count else {
            throw FeatureEvaluationError.missingInput("Curve edit source index could not be resolved.")
        }
        guard case let .bSpline(curve) = curves[source.curveIndex].exactCurve else {
            throw FeatureEvaluationError.unsupportedOperation("Curve edit requires an exact B-spline curve.")
        }
        return curve
    }

    private func apply(_ edit: CurveEdit, to curve: inout BSplineCurve3D) throws {
        switch edit {
        case let .setControlPoint(edit):
            guard curve.controlPoints.indices.contains(edit.target.controlPointIndex) else {
                throw FeatureEvaluationError.missingInput("Curve control point edit index could not be resolved.")
            }
            curve.controlPoints[edit.target.controlPointIndex] = edit.point
        case let .setKnot(edit):
            guard curve.knots.indices.contains(edit.target.knotIndex) else {
                throw FeatureEvaluationError.missingInput("Curve knot edit index could not be resolved.")
            }
            curve.knots[edit.target.knotIndex] = edit.value
        case let .setWeight(edit):
            guard curve.weights.indices.contains(edit.target.controlPointIndex) else {
                throw FeatureEvaluationError.missingInput("Curve weight edit index could not be resolved.")
            }
            curve.weights[edit.target.controlPointIndex] = edit.value
        }
    }

    private func evaluatedCurve(
        featureID: FeatureID,
        curve: BSplineCurve3D,
        sampleCount: Int,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        guard sampleCount >= 2 else {
            throw GeometryError.invalidDistance(Double(sampleCount))
        }
        guard case let .closed(lowerBound, upperBound) = curve.domain else {
            throw FeatureEvaluationError.unsupportedOperation("B-spline curve edit requires a bounded curve domain.")
        }
        let span = upperBound - lowerBound
        let points = try (0..<sampleCount).map { index in
            try curve.point(
                at: lowerBound + span * Double(index) / Double(sampleCount - 1),
                tolerance: tolerance
            )
        }
        let evaluated = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: .spline,
            points: points,
            exactCurve: .bSpline(curve)
        )
        try evaluated.validate(tolerance: tolerance)
        return evaluated
    }
}
