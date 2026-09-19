import CADCore
import CADGeometry
import CADIR

public struct SpatialPathFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let sampler: any DerivedCurveSampling

    public init(sampler: any DerivedCurveSampling = UniformDerivedCurveSampler()) {
        self.sampler = sampler
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode, context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            guard case let .spatialPath(path) = feature.operation else {
                throw FeatureEvaluationError.invalidGraph("Spatial path evaluation requires spatial path source.")
            }
            let exact = try path.exactCurve(tolerance: context.tolerance)
            var points: [Point3D] = []
            if path.kind == .polyline {
                points = path.knots.map(\.position)
                if path.isClosed { points.append(path.knots[0].position) }
            } else {
                // Sample each span so no authored join disappears between uniform samples.
                for segment in 0..<path.segmentCount {
                    let samples = try sampler.points(
                        for: exact, domain: .closed(Double(segment), Double(segment + 1)),
                        tolerance: context.tolerance
                    )
                    points.append(contentsOf: segment == 0 ? samples[...] : samples.dropFirst())
                }
            }
            let curve = EvaluatedCurve(
                sourceFeatureID: feature.id, source: .generatedFeature,
                kind: .spline, points: points, plane: nil, exactCurve: .bSpline(exact)
            )
            try curve.validate(tolerance: context.tolerance)
            return EvaluationResult(brep: context.brep, generatedCurves: [curve])
        }
    }
}
