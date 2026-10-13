#if canImport(Foundation)
import Foundation
#else
import WASILibc
#endif
import CADCore
import CADGeometry
import CADIR
import CADTopology

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
        let sourceBudget = try CurvedSweepSourceBudget(tolerance: context.tolerance)
        let admission = try sourceBudget.conversionAdmission()
        let source = try sourceCurve(curveTrim.source, featureID: feature.id, context: context,
            admission: admission)
        let generatedCurve = try trimmedCurve(
            featureID: feature.id,
            source: source,
            domain: curveTrim.domain,
            tolerance: context.tolerance,
            admission: admission
        )
        try admission.chargeStorage(bytes: MemoryLayout<EvaluatedCurve>.stride)
        var result = EvaluationResult(
            brep: context.brep,
            generatedCurves: [generatedCurve]
        )
        result.validatedBRep = context.validatedBRep
        return result
    }

    private func sourceCurve(
        _ reference: CurveOutputReference,
        featureID: FeatureID,
        context: EvaluationContext,
        admission: GeometryConversionAdmission
    ) throws -> EvaluatedCurve {
        try reference.validate()
        guard let curves = context.curves[reference.featureID] else {
            throw kernelError(.missingReference, featureID: featureID, tolerance: context.tolerance, "Curve trim source feature could not be resolved.")
        }
        guard reference.curveIndex < curves.count else {
            throw kernelError(.missingReference, featureID: featureID, tolerance: context.tolerance, "Curve trim source index could not be resolved.")
        }
        let curve = curves[reference.curveIndex]
        try admission.chargeWork()
        guard curve.exactCurve != nil else {
            throw kernelError(.missingReference, featureID: featureID, tolerance: context.tolerance, "Curve trim source does not contain exact curve geometry.")
        }
        return curve
    }

    package func trimmedCurve(
        featureID: FeatureID,
        source: EvaluatedCurve,
        domain: ParameterDomain,
        tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission? = nil
    ) throws -> EvaluatedCurve {
        guard let exactCurve = source.exactCurve else {
            throw kernelError(.missingReference, featureID: featureID, tolerance: tolerance, "Curve trim source does not contain exact curve geometry.")
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
        let samples: (points: [Point3D], parameters: [Double])
        let closed: Bool
        let kind: EvaluatedCurveKind
        if let admission {
            _ = try source.validateOriginalGeometry(tolerance: tolerance,
                maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                remainingSourceDepth: admission.remainingSourceDepth,
                consumeWork: { try admission.visit(depth: $0) },
                consumeStorage: { try admission.chargeStorage(bytes: $0) },
                maximumAlgebraicDepth: admission.maximumAlgebraicDepth)
            samples = try samplePoints(exactCurve, lowerBound: lowerBound, upperBound: upperBound,
                tolerance: tolerance, admission: admission)
            closed = try BRepEdgeGeometryClassifier(maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                remainingSourceDepth: admission.remainingSourceDepth,
                consumeWork: { try admission.visit(depth: $0) },
                consumeStorage: { try admission.chargeStorage(bytes: $0) },
                maximumAlgebraicDepth: admission.maximumAlgebraicDepth)
                .kind(curve: exactCurve, from: lowerBound, to: upperBound, tolerance: tolerance) == .closed
            kind = try boundedTrimmedKind(sourceKind: source.kind, curve: exactCurve,
                isClosed: closed, remainingSourceDepth: admission.remainingSourceDepth, admission: admission)
        } else {
            samples = try samplePoints(exactCurve, lowerBound: lowerBound, upperBound: upperBound, tolerance: tolerance)
            closed = trimmedCurveIsClosed(source: source, exactCurve: exactCurve,
                lowerBound: lowerBound, upperBound: upperBound, tolerance: tolerance)
            kind = try trimmedKind(sourceKind: source.kind, exactCurve: exactCurve,
                lowerBound: lowerBound, upperBound: upperBound, tolerance: tolerance)
        }
        let evaluated = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: kind,
            points: samples.points,
            isClosed: closed,
            plane: source.plane,
            exactCurve: exactCurve,
            exactParameterDomain: domain,
            exactPointParameters: samples.parameters
        )
        // The admitted route preserves the already validated raw curve, binds
        // this contained domain above and proves every new display position.
        // Replaying source preparation here would not establish a new premise.
        if admission == nil { try evaluated.validate(tolerance: tolerance) }
        return evaluated
    }

    private func samplePoints(_ curve: Curve3D, lowerBound: Double, upperBound: Double,
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws
        -> (points: [Point3D], parameters: [Double]) {
        guard lowerBound.isFinite, upperBound.isFinite, lowerBound < upperBound else {
            throw GeometryConversionError.invalidInput("Original trim samples require distinct finite authored endpoints.")
        }
        let prepared = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
            remainingSourceDepth: admission.remainingSourceDepth,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            consumeWork: { try admission.chargeWork() }, consumeStorage: { try admission.chargeStorage(bytes: $0) })
        let count = 33
        try admission.chargeStorage(bytes: count * (MemoryLayout<Point3D>.stride + MemoryLayout<Double>.stride))
        var points: [Point3D] = [], parameters: [Double] = []
        points.reserveCapacity(count); parameters.reserveCapacity(count)
        for index in 0..<count {
            try admission.chargeWork()
            let fraction = Double(index) / Double(count - 1)
            let parameter = index == 0 ? lowerBound : (index == count - 1 ? upperBound
                : lowerBound * (1 - fraction) + upperBound * fraction)
            guard parameter.isFinite, parameter >= lowerBound, parameter <= upperBound else {
                throw GeometryConversionError.invalidInput("Original trim sample station escaped its authored interval.")
            }
            let enclosure = try prepared.closedNativeJets(over: ScalarInterval(lower: parameter, upper: parameter),
                tolerance: tolerance, maximumSpanCount: admission.maximumSpanCount,
                maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                remainingSourceDepth: admission.remainingSourceDepth,
                consumeWork: { try admission.chargeWork() }, consumeStorage: { try admission.chargeStorage(bytes: $0) })
            var position: IntervalVector3DBounds?
            for owner in enclosure.spans {
                try admission.chargeWork()
                let next = IntervalVector3DBounds(x: owner.jet.x.value, y: owner.jet.y.value, z: owner.jet.z.value)
                if let previous = position {
                    func hull(_ a: OutwardScalarInterval, _ b: OutwardScalarInterval) -> OutwardScalarInterval {
                        .init(lower: min(a.lower, b.lower), upper: max(a.upper, b.upper))
                    }
                    position = .init(x: hull(previous.x, next.x), y: hull(previous.y, next.y), z: hull(previous.z, next.z))
                } else { position = next }
            }
            guard let position, position.x.isFinite, position.y.isFinite, position.z.isFinite else {
                throw GeometryConversionError.resourceLimitExceeded("Original trim sample lacks a complete finite native enclosure.")
            }
            let point = Point3D(x: position.x.midpoint, y: position.y.midpoint, z: position.z.midpoint)
            guard IntervalVector3DBounds(x: position.x - .exact(point.x), y: position.y - .exact(point.y),
                z: position.z - .exact(point.z)).lengthUpperBound <= tolerance.distance / 64 else {
                throw GeometryConversionError.toleranceRejected
            }
            points.append(point); parameters.append(parameter)
        }
        return (points, parameters)
    }

    private func boundedTrimmedKind(sourceKind: EvaluatedCurveKind, curve: Curve3D,
        isClosed: Bool, remainingSourceDepth: Int, admission: GeometryConversionAdmission) throws -> EvaluatedCurveKind {
        try admission.chargeWork()
        guard remainingSourceDepth >= 0 else { throw GeometryConversionError.resourceLimitExceeded("Original trim metadata exhausted source depth.") }
        switch curve {
        case .line, .analytic(.line): return .line
        case .circle, .analytic(.circle): return isClosed ? .circle : .arc
        case .analytic(.arc): return .arc
        case .bSpline: return sourceKind == .arc ? .spline : sourceKind
        case .rigidImage(let image):
            return try boundedTrimmedKind(sourceKind: sourceKind, curve: image.source, isClosed: isClosed,
                remainingSourceDepth: remainingSourceDepth - 1, admission: admission)
        case .parameterImage(let image):
            return try boundedTrimmedKind(sourceKind: sourceKind, curve: image.source, isClosed: isClosed,
                remainingSourceDepth: remainingSourceDepth - 1, admission: admission)
        case .originalAngularTransport(let image):
            return try boundedTrimmedKind(sourceKind: sourceKind, curve: image.source, isClosed: isClosed,
                remainingSourceDepth: remainingSourceDepth - 1, admission: admission)
        case .affineImage, .originalAffineWord: return curve.hasExactLinearParameterization ? .line : .spline
        case .analytic, .implicit, .surfaceLift, .certifiedIntersection, .originalEndpointConnector,
             .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline,
             .originalConstructionChart, .originalPlaneDerivative, .originalDrafted:
            return .spline
        }
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
    ) throws -> (points: [Point3D], parameters: [Double]) {
        let span = upperBound - lowerBound
        guard span.isFinite, span > 0 else {
            throw GeometryError.invalidDistance(span)
        }
        let sampleCount = 33
        let parameters = (0..<sampleCount).map { index in
            let parameter: Double
            if index == 0 {
                parameter = lowerBound
            } else if index == sampleCount - 1 {
                parameter = upperBound
            } else {
                parameter = lowerBound
                    + span * Double(index) / Double(sampleCount - 1)
            }
            return parameter
        }
        return (try parameters.map { try curve.point(at: $0, tolerance: tolerance) }, parameters)
    }

    private func trimmedKind(
        sourceKind: EvaluatedCurveKind,
        exactCurve: Curve3D,
        lowerBound: Double,
        upperBound: Double,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurveKind {
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
        case .implicit, .surfaceLift, .certifiedIntersection, .originalEndpointConnector,
             .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline,
             .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted:
            return .spline
        case let .rigidImage(image):
            return try trimmedKind(
                sourceKind: sourceKind,
                exactCurve: image.source,
                lowerBound: lowerBound,
                upperBound: upperBound,
                tolerance: tolerance
            )
        case .affineImage, .originalAffineWord:
            return exactCurve.hasExactLinearParameterization ? .line : .spline
        case let .parameterImage(image):
            let first = try image.sourceParameter(at: lowerBound, tolerance: tolerance)
            let last = try image.sourceParameter(at: upperBound, tolerance: tolerance)
            return try trimmedKind(sourceKind: sourceKind, exactCurve: image.source,
                lowerBound: min(first, last), upperBound: max(first, last), tolerance: tolerance)
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
