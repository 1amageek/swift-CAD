import CADCore
import CADGeometry

/// Extends a chart's actual parameter law without fitting a replacement curve.
package struct OriginalOffsetCurveContinuation {
    package init() {}

    package func curve(_ original: SurfaceParameterCurve, from lower: Double, to upper: Double,
               tolerance: ModelingTolerance) throws -> SurfaceParameterCurve {
        try Task.checkCancellation()
        try tolerance.validate()
        guard lower.isFinite, upper.isFinite, lower != upper else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original chart continuation needs a finite non-degenerate directed interval.")
        }
        switch original {
        case let .constantU(u, a, b):
            return .constantU(u: u, vStart: a + (b - a) * lower, vEnd: a + (b - a) * upper)
        case let .constantV(v, a, b):
            return .constantV(v: v, uStart: a + (b - a) * lower, uEnd: a + (b - a) * upper)
        case let .affine(origin, direction, a, b):
            return .affine(origin: origin, direction: direction,
                startParameter: a + (b - a) * lower, endParameter: a + (b - a) * upper)
        case let .harmonic(center, cosine, sine, a, b):
            return .harmonic(center: center, cosine: cosine, sine: sine,
                startParameter: a + (b - a) * lower, endParameter: a + (b - a) * upper)
        case let .bSpline(source):
            guard case let .closed(a, b) = source.domain else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "Natural spline joining requires a finite native source interval.")
            }
            return .originalBSplineContinuation(try OriginalBSplineCurve2DContinuation(original: source,
                startParameter: a + (b - a) * lower, endParameter: a + (b - a) * upper, tolerance: tolerance))
        case let .originalBSplineContinuation(source):
            return .originalBSplineContinuation(try OriginalBSplineCurve2DContinuation(original: source.original,
                startParameter: source.startParameter + (source.endParameter - source.startParameter) * lower,
                endParameter: source.startParameter + (source.endParameter - source.startParameter) * upper, tolerance: tolerance))
        case .polyline:
            // FIXME(INCOMPLETE_IMPLEMENTATION): EdgeOffset and FaceLoopOffset
            // Natural joining must retain the original Euclidean arc-length
            // prefix and endpoint segment continuation. A uniform index-knot
            // spline changes that law, and rounded length knots cannot establish
            // the required original parameter correspondence.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Natural polyline joining requires the retained original length-prefix continuation producer.")
        case let .periodicTranslation(base, uShift, vShift):
            return .periodicTranslation(base: try curve(base, from: lower, to: upper, tolerance: tolerance),
                uShift: uShift, vShift: vShift)
        case let .originalImage(image):
            let scale = image.endFraction - image.startFraction
            let continued = try curve(image.source.parameterCurve,
                from: image.startFraction + scale * lower,
                to: image.startFraction + scale * upper, tolerance: tolerance)
            let lift = SurfaceLiftCurve3D(surface: image.source.surface, parameterCurve: continued)
            return .originalImage(try OriginalImageSurfaceParameterCurve(
                source: lift, targetImage: image.targetImage, tolerance: tolerance))
        case let .originalAffineWord(image):
            let scale = image.endFraction - image.startFraction
            let continued = try curve(image.source.parameterCurve,
                from: image.startFraction + scale * lower,
                to: image.startFraction + scale * upper, tolerance: tolerance)
            return .originalAffineWord(try OriginalAffineWordSurfaceParameterCurve(
                source: SurfaceLiftCurve3D(surface: image.source.surface, parameterCurve: continued),
                target: image.target, tolerance: tolerance))
        case let .rigidImage(image):
            let scale = image.endFraction - image.startFraction
            let continued = try curve(image.source.parameterCurve,
                from: image.startFraction + scale * lower,
                to: image.startFraction + scale * upper, tolerance: tolerance)
            let lift = SurfaceLiftCurve3D(surface: image.source.surface, parameterCurve: continued)
            return .rigidImage(try RigidImageSurfaceParameterCurve(source: lift,
                targetSurface: image.targetSurface, transform: image.transform, tolerance: tolerance))
        case let .offsetSurfaceImage(image):
            let continued = try curve(image.source, from: lower, to: upper, tolerance: tolerance)
            if image.isPullback {
                return .offsetSurfaceImage(try image.offset.parameterCurvePullback(
                    transporting: continued, tolerance: tolerance))
            }
            return .offsetSurfaceImage(try image.offset.parameterCurveImage(
                transporting: continued, tolerance: tolerance))
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Edge Offset and Face Loop Offset call this
            // actual-law continuation owner. Remaining implicit/projected source families need
            // their original continuation domains and complete root certificates before Natural
            // may publish them. No osculating-circle or interpolated fallback is admitted.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "This offset chart family has no admitted original-law continuation domain.")
        }
    }
}
