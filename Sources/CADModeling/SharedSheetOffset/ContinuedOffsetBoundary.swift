#if canImport(Foundation)
import Foundation
#else
import WASILibc
#endif
import CADCore
import CADGeometry

/// Reaches solved joint endpoints by continuing the original boundary law in its offset chart.
struct ContinuedOffsetBoundary {
    func curve(_ original: SurfaceParameterCurve, on surface: Surface3D,
               from start: Point3D, to end: Point3D,
               tolerance: ModelingTolerance) throws -> SurfaceParameterCurve {
        let lift = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: surface, parameterCurve: original))
        let a = try lift.point(at: 0, tolerance: tolerance)
        let b = try lift.point(at: 1, tolerance: tolerance)
        if (a - start).length <= tolerance.distance && (b - end).length <= tolerance.distance { return original }
        let startUV = try surface.parameterProjection(of: start, tolerance: tolerance)
        let endUV = try surface.parameterProjection(of: end, tolerance: tolerance)
        let continued = try continuedChart(original, start: SurfaceParameter(u: startUV.u, v: startUV.v),
            end: SurfaceParameter(u: endUV.u, v: endUV.v), tolerance: tolerance)
        let result = SurfaceLiftCurve3D(surface: surface, parameterCurve: continued)
        guard (try result.point(atNormalizedFraction: 0, tolerance: tolerance) - start).length <= tolerance.distance,
              (try result.point(atNormalizedFraction: 1, tolerance: tolerance) - end).length <= tolerance.distance else {
            throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                message: "The continued offset boundary does not reach its jointly solved vertices.")
        }
        return continued
    }

    private func spline(_ original: BSplineCurve2D, start: SurfaceParameter, end: SurfaceParameter,
                        startSeed: Double, endSeed: Double,
                        tolerance: ModelingTolerance) throws -> SurfaceParameterCurve {
        let source = try OriginalBSplineCurve2DContinuationSource(curve: original, tolerance: tolerance)
        func native(_ endpoint: SurfaceParameter, seed: Double) throws -> Double {
            var parameter = seed
            for _ in 0..<32 {
                try CurrentTaskCancellationChecker().checkCancellation()
                let jet = try source.pointAndDerivative(at: parameter, tolerance: tolerance)
                let delta = Vector3D(x: jet.point.x - endpoint.u, y: jet.point.y - endpoint.v, z: 0)
                if delta.length <= tolerance.distance { return parameter }
                let squared = jet.derivative.dot(jet.derivative)
                guard squared > Double.leastNormalMagnitude else {
                    throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                        message: "An original spline continuation endpoint has no regular native derivative.")
                }
                let next = parameter - delta.dot(jet.derivative) / squared
                guard next.isFinite, next != parameter else {
                    throw KernelError(phase: .geometry, code: .topologyFailure, tolerance: tolerance,
                        message: "The solved vertex does not lie on the original spline continuation law.")
                }
                parameter = next
            }
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original spline continuation endpoint solving exhausted its iteration contract.")
        }
        let a = try native(start, seed: startSeed), b = try native(end, seed: endSeed)
        // Keep the original homogeneous law and oriented native interval. A fitted
        // candidate is never substituted for the source during intersection or publication.
        return .originalBSplineContinuation(try OriginalBSplineCurve2DContinuation(
            original: original, startParameter: a, endParameter: b, tolerance: tolerance))
    }

    private func continuedChart(_ chart: SurfaceParameterCurve, start: SurfaceParameter, end: SurfaceParameter,
                                tolerance: ModelingTolerance) throws -> SurfaceParameterCurve {
        switch chart {
        case let .originalImage(image):
            let nativeStart = try image.targetImage.nativeParameter(u: start.u, v: start.v)
            let nativeEnd = try image.targetImage.nativeParameter(u: end.u, v: end.v)
            let active = try OriginalOffsetCurveContinuation().curve(image.source.parameterCurve,
                from: image.startFraction, to: image.endFraction, tolerance: tolerance)
            let continued = try continuedChart(active, start: nativeStart, end: nativeEnd,
                tolerance: tolerance)
            return .originalImage(try OriginalImageSurfaceParameterCurve(
                source: SurfaceLiftCurve3D(surface: image.source.surface, parameterCurve: continued),
                targetImage: image.targetImage, tolerance: tolerance))
        case let .originalAffineWord(image):
            let active = try OriginalOffsetCurveContinuation().curve(image.source.parameterCurve,
                from: image.startFraction, to: image.endFraction, tolerance: tolerance)
            let continued = try continuedChart(active, start: start, end: end, tolerance: tolerance)
            return .originalAffineWord(try OriginalAffineWordSurfaceParameterCurve(
                source: SurfaceLiftCurve3D(surface: image.source.surface, parameterCurve: continued),
                target: image.target, tolerance: tolerance))
        case let .offsetSurfaceImage(image):
            let source = try continuedChart(image.source, start: start, end: end, tolerance: tolerance)
            if image.isPullback {
                return .offsetSurfaceImage(try image.offset.parameterCurvePullback(
                    transporting: source, tolerance: tolerance))
            }
            return .offsetSurfaceImage(try image.offset.parameterCurveImage(transporting: source, tolerance: tolerance))
        case let .bSpline(original):
            guard case let .closed(lower, upper) = original.domain else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "An original spline continuation requires its finite native source interval.")
            }
            return try spline(original, start: start, end: end, startSeed: lower, endSeed: upper, tolerance: tolerance)
        case let .originalBSplineContinuation(original):
            return try spline(original.original, start: start, end: end,
                startSeed: original.startParameter, endSeed: original.endParameter, tolerance: tolerance)
        case let .constantU(u, _, _):
            return .constantU(u: u, vStart: start.v, vEnd: end.v)
        case let .constantV(v, _, _):
            return .constantV(v: v, uStart: start.u, uEnd: end.u)
        case let .affine(origin, direction, _, _):
            let lengthSquared = direction.x * direction.x + direction.y * direction.y
            guard lengthSquared > Double.leastNormalMagnitude else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "An offset boundary has a degenerate affine parameter law.")
            }
            func parameter(_ uv: SurfaceParameter) -> Double {
                ((uv.u - origin.x) * direction.x + (uv.v - origin.y) * direction.y) / lengthSquared
            }
            return .affine(origin: origin, direction: direction,
                           startParameter: parameter(start), endParameter: parameter(end))
        case let .polyline(points) where points.count == 2:
            return try continuedChart(.affine(origin: Point2D(x: points[0].u, y: points[0].v),
                direction: Point2D(x: points[1].u - points[0].u, y: points[1].v - points[0].v),
                startParameter: 0, endParameter: 1), start: start, end: end, tolerance: tolerance)
        case let .harmonic(center, cosine, sine, lower, upper):
            let determinant = cosine.x * sine.y - cosine.y * sine.x
            guard abs(determinant) > Double.leastNormalMagnitude else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "An offset boundary has a singular harmonic parameter law.")
            }
            func parameter(_ uv: SurfaceParameter, near seed: Double) -> Double {
                let x = uv.u - center.x, y = uv.v - center.y
                let c = (x * sine.y - y * sine.x) / determinant
                let s = (cosine.x * y - cosine.y * x) / determinant
                let angle = atan2(s, c)
                return angle + ((seed - angle) / (2 * .pi)).rounded() * (2 * .pi)
            }
            return .harmonic(center: center, cosine: cosine, sine: sine,
                             startParameter: parameter(start, near: lower), endParameter: parameter(end, near: upper))
        case let .periodicTranslation(base, uShift, vShift):
            return .periodicTranslation(base: try continuedChart(base,
                start: SurfaceParameter(u: start.u - uShift, v: start.v - vShift),
                end: SurfaceParameter(u: end.u - uShift, v: end.v - vShift), tolerance: tolerance),
                uShift: uShift, vShift: vShift)
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): SharedSheetSurfaceOffsetter transports this exact
            // original boundary through FaceSurfaceReplacementRebuilder, but this family cannot
            // yet continue beyond its source interval. Complete only with its exact continuation
            // producer and joint-endpoint/whole-law correspondence validation.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "The original offset boundary law has no exact natural continuation to the solved joint.")
        }
    }
}
