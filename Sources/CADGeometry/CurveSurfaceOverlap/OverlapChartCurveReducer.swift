import CADCore

/// Reduces proven chart-preserving images to a coordinate-independent pcurve.
struct OverlapChartCurveReducer {
    func reduce(_ curve: SurfaceParameterCurve, options: CurveSurfaceIntersectionOptions,
                tolerance: ModelingTolerance) throws -> SurfaceParameterCurve? {
        var remaining = options.maximumSubdivisionCells
        return try reduce(curve, depth: 0, remaining: &remaining, options: options, tolerance: tolerance)
    }

    private func reduce(_ curve: SurfaceParameterCurve, depth: Int, remaining: inout Int,
                        options: CurveSurfaceIntersectionOptions,
                        tolerance: ModelingTolerance) throws -> SurfaceParameterCurve? {
        try Task.checkCancellation()
        guard depth <= options.maximumSubdivisionDepth, remaining > 0 else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Overlap chart-image reduction exceeded its depth or work budget.")
        }
        remaining -= 1
        switch curve {
        case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline, .originalBSplineContinuation:
            return curve
        case let .periodicTranslation(base, uShift, vShift):
            guard let reduced = try reduce(base, depth: depth + 1, remaining: &remaining,
                                           options: options, tolerance: tolerance) else { return nil }
            return .periodicTranslation(base: reduced, uShift: uShift, vShift: vShift)
        case .offsetSurfaceImage(let image):
            return try reduce(image.source, depth: depth + 1, remaining: &remaining,
                              options: options, tolerance: tolerance)
        case .rigidImage(let image):
            guard try image.affineParameterTransform(tolerance: tolerance) == .identity else { return nil }
            return try reduce(image.sourceParameterCurve(tolerance: tolerance), depth: depth + 1,
                              remaining: &remaining, options: options, tolerance: tolerance)
        case .sphericalGreatCircle, .certifiedImplicit, .certifiedAnalyticImplicit,
             .certifiedAnalyticPair, .projectedAnalytic, .originalImage:
            return nil
        }
    }
}
