import CADCore
import CADGeometry
import CADIR

public struct CurveEditFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let sampler: any DerivedCurveSampling

    public init(
        sampler: any DerivedCurveSampling = UniformDerivedCurveSampler()
    ) {
        self.sampler = sampler
    }

    public func evaluate(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try evaluateUnvalidated(feature: feature, context: context)
        }
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard case let .curveEdit(curveEdit) = feature.operation else {
            throw FeatureEvaluationError.invalidGraph(
                "CurveEditFeatureEvaluator requires a curve edit feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try curveEdit.validate(tolerance: context.tolerance)
        }

        var sourceCurve = try exactBSpline(source: curveEdit.source, context: context)
        for edit in curveEdit.edits {
            try apply(edit, to: &sourceCurve.curve)
        }
        try sourceCurve.curve.validate(tolerance: context.tolerance)

        let generatedCurve = try evaluatedCurve(
            featureID: feature.id,
            curve: sourceCurve.curve,
            plane: sourceCurve.plane,
            domain: sourceCurve.domain,
            tolerance: context.tolerance
        )
        return EvaluationResult(
            brep: context.brep,
            generatedCurves: [generatedCurve]
        )
    }

    private func exactBSpline(
        source: CurveOutputReference,
        context: EvaluationContext
    ) throws -> (curve: BSplineCurve3D, plane: SketchPlane?, domain: ParameterDomain?) {
        try source.validate()
        guard let curves = context.curves[source.featureID] else {
            throw FeatureEvaluationError.missingInput("Curve edit source feature could not be resolved.")
        }
        guard source.curveIndex < curves.count else {
            throw FeatureEvaluationError.missingInput("Curve edit source index could not be resolved.")
        }
        let sourceCurve = curves[source.curveIndex]
        try sourceCurve.validate(tolerance: context.tolerance)
        guard case let .bSpline(curve) = sourceCurve.exactCurve else {
            throw FeatureEvaluationError.missingInput(
                "Curve edit target does not expose B-spline control points, knots, or weights."
            )
        }
        return (
            curve: curve,
            plane: sourceCurve.plane,
            domain: sourceCurve.exactParameterDomain
        )
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
        plane: SketchPlane?,
        domain: ParameterDomain?,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        let points = try sampler.points(
            for: curve,
            domain: domain,
            tolerance: tolerance
        )
        let evaluated = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: .spline,
            points: points,
            plane: plane,
            exactCurve: .bSpline(curve),
            exactParameterDomain: domain
        )
        try evaluated.validate(tolerance: tolerance)
        return evaluated
    }
}
