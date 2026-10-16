import CADCore

/// Reduces proven chart-preserving images to a coordinate-independent pcurve.
struct OverlapChartCurveReducer {
    func reduce(_ curve: SurfaceParameterCurve, options: CurveSurfaceIntersectionOptions,
                tolerance: ModelingTolerance) throws -> SurfaceParameterCurve? {
        var execution = try OriginalQueryExecution.independentGeometry()
        let policy = try OverlapProofPolicy(options: options, tolerance: tolerance, using: &execution)
        return try reduce(curve, options: options, tolerance: tolerance, policy: policy, using: &execution)
    }

    func reduce(_ curve: SurfaceParameterCurve, options: CurveSurfaceIntersectionOptions,
                tolerance: ModelingTolerance, policy: OverlapProofPolicy,
                using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurve? {
        try reduce(curve, depth: 0, policy: policy, options: options, tolerance: tolerance, using: &execution)
    }

    private func reduce(_ curve: SurfaceParameterCurve, depth: Int, policy: OverlapProofPolicy,
                        options: CurveSurfaceIntersectionOptions,
                        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurve? {
        try execution.checkpoint()
        try policy.depth(depth, using: &execution)
        try policy.work(using: &execution)
        switch curve {
        case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline, .originalBSplineContinuation:
            return curve
        case let .periodicTranslation(base, uShift, vShift):
            guard let reduced = try reduce(base, depth: depth + 1, policy: policy,
                                           options: options, tolerance: tolerance, using: &execution) else { return nil }
            return .periodicTranslation(base: reduced, uShift: uShift, vShift: vShift)
        case .offsetSurfaceImage(let image):
            return try reduce(image.source, depth: depth + 1, policy: policy,
                              options: options, tolerance: tolerance, using: &execution)
        case .rigidImage(let image):
            guard try image.affineParameterTransform(tolerance: tolerance, using: &execution) == .identity else { return nil }
            return try reduce(image.sourceParameterCurve(tolerance: tolerance, using: &execution), depth: depth + 1,
                              policy: policy, options: options, tolerance: tolerance, using: &execution)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Production overlap reduction lacks
        // admitted coordinate-independent transport for hosted flat-word pcurves.
        // Target binding and directed original fractions must both be retained
        // before this family can reduce; spatial word binding alone is insufficient.
        case .originalAffineWord:
            return nil
        case .sphericalGreatCircle, .certifiedImplicit, .certifiedAnalyticImplicit,
             .certifiedAnalyticPair, .projectedAnalytic, .originalImage:
            return nil
        }
    }
}
