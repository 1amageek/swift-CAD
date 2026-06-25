import Foundation
import CADCore
import CADIR

public struct CurveTrimFeatureEvaluator: FeatureEvaluating {
    public init() {}

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .curveTrim(curveTrim) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation("CurveTrimFeatureEvaluator requires a curve trim feature.")
        }
        try curveTrim.validate(tolerance: context.tolerance)
        let source = try sourceCurve(curveTrim.source, context: context)
        let generatedCurve = try trimmedCurve(
            featureID: feature.id,
            source: source,
            domain: curveTrim.domain,
            sampleCount: curveTrim.sampleCount,
            tolerance: context.tolerance
        )
        return EvaluationResult(
            brep: context.brep,
            generatedNames: [:],
            generatedCurves: [generatedCurve]
        )
    }

    private func sourceCurve(
        _ reference: CurveOutputReference,
        context: EvaluationContext
    ) throws -> EvaluatedCurve {
        try reference.validate()
        guard let curves = context.curves[reference.featureID] else {
            throw FeatureEvaluationError.missingInput("Curve trim source feature could not be resolved.")
        }
        guard reference.curveIndex < curves.count else {
            throw FeatureEvaluationError.missingInput("Curve trim source index could not be resolved.")
        }
        let curve = curves[reference.curveIndex]
        try curve.validate(tolerance: context.tolerance)
        guard curve.exactCurve != nil else {
            throw FeatureEvaluationError.unsupportedOperation("Curve trim requires an exact source curve.")
        }
        return curve
    }

    private func trimmedCurve(
        featureID: FeatureID,
        source: EvaluatedCurve,
        domain: ParameterDomain,
        sampleCount: Int,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        guard let exactCurve = source.exactCurve else {
            throw FeatureEvaluationError.unsupportedOperation("Curve trim requires an exact source curve.")
        }
        guard case let .closed(lowerBound, upperBound) = domain else {
            throw FeatureEvaluationError.invalidGraph("Curve trim requires a finite closed parameter domain.")
        }
        guard try source.parameterDomain.containsSpan(from: lowerBound, to: upperBound, tolerance: tolerance) else {
            throw FeatureEvaluationError.invalidGraph("Curve trim domain must be contained in the source curve domain.")
        }
        let points = try samplePoints(
            exactCurve,
            lowerBound: lowerBound,
            upperBound: upperBound,
            sampleCount: sampleCount,
            tolerance: tolerance
        )
        let kind = trimmedKind(
            sourceKind: source.kind,
            exactCurve: exactCurve,
            lowerBound: lowerBound,
            upperBound: upperBound,
            tolerance: tolerance
        )
        let evaluated = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: kind,
            points: points,
            isClosed: trimmedCurveIsClosed(
                source: source,
                exactCurve: exactCurve,
                lowerBound: lowerBound,
                upperBound: upperBound,
                tolerance: tolerance
            ),
            plane: source.plane,
            exactCurve: exactCurve,
            exactParameterDomain: domain
        )
        try evaluated.validate(tolerance: tolerance)
        return evaluated
    }

    private func samplePoints(
        _ curve: Curve3D,
        lowerBound: Double,
        upperBound: Double,
        sampleCount: Int,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        let span = upperBound - lowerBound
        guard span > tolerance.distance else {
            throw GeometryError.invalidDistance(span)
        }
        return try (0..<sampleCount).map { index in
            try curve.point(
                at: lowerBound + span * Double(index) / Double(sampleCount - 1),
                tolerance: tolerance
            )
        }
    }

    private func trimmedKind(
        sourceKind: EvaluatedCurveKind,
        exactCurve: Curve3D,
        lowerBound: Double,
        upperBound: Double,
        tolerance: ModelingTolerance
    ) -> EvaluatedCurveKind {
        switch exactCurve {
        case .circle:
            let span = upperBound - lowerBound
            if span >= Double.pi * 2.0 - tolerance.angle {
                return .circle
            }
            return .arc
        case .line:
            return .line
        case .bSpline:
            return sourceKind == .arc ? .spline : sourceKind
        }
    }

    private func trimmedCurveIsClosed(
        source: EvaluatedCurve,
        exactCurve: Curve3D,
        lowerBound: Double,
        upperBound: Double,
        tolerance: ModelingTolerance
    ) -> Bool {
        if case .circle = exactCurve {
            return upperBound - lowerBound >= Double.pi * 2.0 - tolerance.angle
        }
        guard source.isClosed else {
            return false
        }
        guard case let .closed(sourceLower, sourceUpper) = source.parameterDomain else {
            return false
        }
        return abs(sourceLower - lowerBound) <= tolerance.distance
            && abs(sourceUpper - upperBound) <= tolerance.distance
    }
}
