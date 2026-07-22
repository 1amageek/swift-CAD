import Foundation
import CADCore
import CADGeometry
import CADIR

public struct CurveTrimFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    public init() {}

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
        guard case let .curveTrim(curveTrim) = feature.operation else {
            throw kernelError(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Curve trim evaluator requires a curveTrim feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try curveTrim.validate(tolerance: context.tolerance)
        }
        let source = try sourceCurve(curveTrim.source, featureID: feature.id, context: context)
        let generatedCurve = try trimmedCurve(
            featureID: feature.id,
            source: source,
            domain: curveTrim.domain,
            tolerance: context.tolerance
        )
        return EvaluationResult(
            brep: context.brep,
            generatedCurves: [generatedCurve]
        )
    }

    private func sourceCurve(
        _ reference: CurveOutputReference,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluatedCurve {
        try reference.validate()
        guard let curves = context.curves[reference.featureID] else {
            throw kernelError(.missingReference, featureID: featureID, tolerance: context.tolerance, "Curve trim source feature could not be resolved.")
        }
        guard reference.curveIndex < curves.count else {
            throw kernelError(.missingReference, featureID: featureID, tolerance: context.tolerance, "Curve trim source index could not be resolved.")
        }
        let curve = curves[reference.curveIndex]
        try curve.validate(tolerance: context.tolerance)
        guard curve.exactCurve != nil else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Curve trim requires an exact source curve.")
        }
        return curve
    }

    private func trimmedCurve(
        featureID: FeatureID,
        source: EvaluatedCurve,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        guard let exactCurve = source.exactCurve else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance, "Curve trim requires an exact source curve.")
        }
        guard case let .closed(lowerBound, upperBound) = domain else {
            throw kernelError(.invalidInput, featureID: featureID, tolerance: tolerance, "Curve trim requires a finite closed parameter domain.")
        }
        guard try containsTrimSpan(
            source.parameterDomain,
            lowerBound: lowerBound,
            upperBound: upperBound,
            tolerance: tolerance
        ) else {
            throw kernelError(.invalidInput, featureID: featureID, tolerance: tolerance, "Curve trim domain must be contained in the source curve domain.")
        }
        let points = try samplePoints(
            exactCurve,
            lowerBound: lowerBound,
            upperBound: upperBound,
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

    private func containsTrimSpan(
        _ sourceDomain: ParameterDomain,
        lowerBound: Double,
        upperBound: Double,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard try sourceDomain.containsSpan(
            from: lowerBound,
            to: upperBound,
            tolerance: tolerance
        ) else {
            return false
        }
        guard case let .periodic(period) = sourceDomain else {
            return true
        }
        let scale = max(abs(lowerBound), abs(upperBound), period, 1.0)
        let parameterTolerance = max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 256.0
        )
        return upperBound - lowerBound <= period + parameterTolerance
    }

    private func samplePoints(
        _ curve: Curve3D,
        lowerBound: Double,
        upperBound: Double,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        let span = upperBound - lowerBound
        guard span > tolerance.distance else {
            throw GeometryError.invalidDistance(span)
        }
        let sampleCount = 33
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
        case .circle, .analytic(.circle):
            let span = upperBound - lowerBound
            if span >= Double.pi * 2.0 - tolerance.angle {
                return .circle
            }
            return .arc
        case .analytic(.arc):
            return .arc
        case .analytic(.ellipse), .analytic(.hyperbola), .analytic(.parabola):
            return .spline
        case .analytic(.planeTorus):
            return .spline
        case .line, .analytic(.line):
            return .line
        case .bSpline:
            return sourceKind == .arc ? .spline : sourceKind
        case .implicit, .surfaceLift:
            return .spline
        }
    }

    private func trimmedCurveIsClosed(
        source: EvaluatedCurve,
        exactCurve: Curve3D,
        lowerBound: Double,
        upperBound: Double,
        tolerance: ModelingTolerance
    ) -> Bool {
        if case let .periodic(period) = exactCurve.parameterDomain {
            return upperBound - lowerBound >= period - tolerance.angle
        }
        if case .analytic(.ellipse) = exactCurve {
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

    private func kernelError(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: .evaluation,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }
}
