import CADCore
import CADIR

public struct CurveDrivenPatternFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let rebuilder: any ExactPlanarPatternRebuilding

    public init(sewer: any BRepSewing = DefaultBRepSewer()) {
        self.rebuilder = DefaultExactPlanarPatternRebuilder(sewer: sewer)
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
        guard case let .curveDrivenPattern(pattern) = feature.operation else {
            throw error(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Curve-driven pattern evaluator requires a curveDrivenPattern feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try pattern.validate(tolerance: context.tolerance)
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context.brep,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        guard let curves = context.curves[pattern.path.featureID], curves.isEmpty == false else {
            throw error(
                .missingReference,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Curve-driven pattern path could not be resolved."
            )
        }
        let samples = try pathSamples(
            curves: curves,
            count: pattern.count,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let transforms = try samples.map { sample in
            try ExactPatternTransform.followingPath(
                anchor: pattern.anchor,
                referenceDirection: pattern.referenceDirection,
                pathPoint: sample.point,
                pathTangent: sample.tangent,
                tolerance: context.tolerance
            )
        }
        let bodyID = try targetBodyID(pattern.target.featureID, featureID: feature.id, context: context)
        return try rebuilder.rebuild(
            featureID: feature.id,
            sourceBodyID: bodyID,
            transforms: transforms,
            stablePrefix: "curveDrivenPattern",
            context: context
        )
    }

    private func pathSamples(
        curves: [EvaluatedCurve],
        count: Int,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> [EvaluatedCurvePathSample] {
        do {
            let segments = try EvaluatedCurveChainBuilder(tolerance: tolerance).openSegments(
                from: curves,
                operationName: "Curve-driven pattern path"
            )
            let evaluator = EvaluatedCurvePathEvaluator(tolerance: tolerance)
            let fullSamples = try evaluator.samples(for: segments)
            guard let first = fullSamples.first else {
                throw error(
                    .topologyFailure,
                    featureID: featureID,
                    tolerance: tolerance,
                    "Curve-driven pattern path produced no samples."
                )
            }
            var result = [first]
            result.reserveCapacity(count)
            for index in 1..<count {
                let fraction = Double(index) / Double(count - 1)
                guard let sample = try evaluator.samples(
                    for: segments,
                    distanceFraction: fraction
                ).last else {
                    throw error(
                        .topologyFailure,
                        featureID: featureID,
                        tolerance: tolerance,
                        "Curve-driven pattern path fraction produced no sample."
                    )
                }
                result.append(sample)
            }
            return result
        } catch let kernelError as KernelError {
            throw kernelError
        } catch {
            throw self.error(
                .unsupportedCapability,
                featureID: featureID,
                tolerance: tolerance,
                "Curve-driven pattern requires one connected open path supported by exact path evaluation: \(error)"
            )
        }
    }

    private func targetBodyID(
        _ sourceFeatureID: FeatureID,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        try context.bodyID(generatedBy: sourceFeatureID)
    }

    private func error(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .evaluation,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }
}
