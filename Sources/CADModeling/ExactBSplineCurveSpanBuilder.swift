import Foundation
import CADCore
import CADGeometry
import CADIR

package struct ExactBSplineCurveSpanBuilder: Sendable {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func profileLoopSpans(
        from profile: Profile
    ) throws -> [[ExactBSplineCurveSpan]] {
        try profile.boundaryLoops.map { loop in
            try profileSpans(from: loop)
        }
    }

    package func profileSpans(
        from loop: ProfileLoop
    ) throws -> [ExactBSplineCurveSpan] {
        try tolerance.validate()
        var result: [ExactBSplineCurveSpan] = []
        for boundary in loop.boundarySegments {
            switch boundary {
            case let .line(line):
                result.append(try lineSpan(
                    from: line.start,
                    to: line.end
                ))
            case let .circularArc(arc):
                let circle = Circle3D(
                    center: arc.center,
                    normal: arc.normal,
                    radius: arc.radius
                )
                let exactCircle = Curve3D.circle(circle)
                let start = try exactCircle.parameterProjection(
                    of: arc.start,
                    tolerance: tolerance
                ).parameter
                result.append(contentsOf: try conicSpans(
                    curve: exactCircle,
                    center: circle.center,
                    lower: start,
                    upper: start + arc.sweepAngle
                ))
            case let .spline(spline):
                result.append(contentsOf: try bSplineSpans(
                    spline.curve,
                    requestedDomain: spline.curve.domain
                ))
            }
        }
        guard result.count >= 2 else {
            throw SketchError.openProfile
        }
        try validateClosure(result)
        return result
    }

    package func pathSpans(
        from segments: [EvaluatedCurvePathSegment],
        endingAt requestedEndPoint: Point3D? = nil
    ) throws -> [ExactBSplineCurveSpan] {
        try tolerance.validate()
        guard segments.isEmpty == false else {
            throw FeatureEvaluationError.missingInput(
                "Exact sweep requires at least one path segment."
            )
        }
        var result: [ExactBSplineCurveSpan] = []
        for segment in segments {
            try segment.validate(tolerance: tolerance)
            guard let curve = segment.curve.exactCurve,
                  case let .closed(lower, upper) = segment.curve.parameterDomain else {
                throw KernelError(
                    phase: .geometry,
                    code: .unsupportedCapability,
                    tolerance: tolerance,
                    message: "Exact sweep requires a bounded exact path curve."
                )
            }
            var spans = try spans(
                curve: curve,
                lower: lower,
                upper: upper
            )
            if segment.isReversed {
                spans = try spans.reversed().map { span in
                    try ExactBSplineCurveSpan(
                        curve: span.curve.reversed(tolerance: tolerance),
                        tolerance: tolerance
                    )
                }
            }
            result.append(contentsOf: spans)
        }
        try validatePathContinuity(result)
        if let requestedEndPoint {
            result = try prefix(
                of: result,
                endingAt: requestedEndPoint
            )
        }
        guard let first = result.first,
              let last = result.last,
              first.startPoint.isApproximatelyEqual(
                to: last.endPoint,
                tolerance: tolerance.distance
              ) == false else {
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Exact translational sweep currently requires an open path."
            )
        }
        return result
    }

    package func sectionSpans(
        from section: EvaluatedCurve
    ) throws -> [ExactBSplineCurveSpan] {
        try tolerance.validate()
        try section.validate(tolerance: tolerance)
        guard let curve = section.exactCurve else {
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Exact sweep sheet sections require exact curve geometry."
            )
        }
        let bounds: (lower: Double, upper: Double)
        switch section.parameterDomain {
        case let .closed(lower, upper):
            bounds = (lower, upper)
        case let .periodic(period):
            guard section.isClosed else {
                throw KernelError(
                    phase: .geometry,
                    code: .unsupportedCapability,
                    tolerance: tolerance,
                    message: "Exact sweep periodic sheet sections require an explicit closed trim."
                )
            }
            bounds = (0.0, period)
        case .unbounded:
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Exact sweep sheet sections require a bounded trim."
            )
        }
        let result = try spans(
            curve: curve,
            lower: bounds.lower,
            upper: bounds.upper
        )
        try validatePathContinuity(result)
        if section.isClosed {
            guard let first = result.first,
                  let last = result.last,
                  first.startPoint.isApproximatelyEqual(
                    to: last.endPoint,
                    tolerance: tolerance.distance
                  ) else {
                throw SketchError.openProfile
            }
        }
        return result
    }

    private func prefix(
        of spans: [ExactBSplineCurveSpan],
        endingAt requestedEndPoint: Point3D
    ) throws -> [ExactBSplineCurveSpan] {
        try requestedEndPoint.validate()
        var result: [ExactBSplineCurveSpan] = []
        for span in spans {
            if span.startPoint.isApproximatelyEqual(
                to: requestedEndPoint,
                tolerance: tolerance.distance
            ) {
                guard result.isEmpty == false else {
                    throw FeatureEvaluationError.invalidDistance(0.0)
                }
                return result
            }
            if span.endPoint.isApproximatelyEqual(
                to: requestedEndPoint,
                tolerance: tolerance.distance
            ) {
                result.append(span)
                return result
            }
            let parameter: Double
            do {
                parameter = try Curve3D.bSpline(span.curve).parameterProjection(
                    of: requestedEndPoint,
                    tolerance: tolerance
                ).parameter
            } catch let error as KernelError where error.code == .intersectionFailure {
                result.append(span)
                continue
            }
            guard case let .closed(lower, upper) = span.curve.domain else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Exact sweep path span lost its bounded domain."
                )
            }
            let parameterTolerance = max(
                tolerance.angle,
                Double.ulpOfOne * max(abs(lower), abs(upper), 1.0) * 64.0
            )
            guard parameter > lower + parameterTolerance,
                  parameter < upper - parameterTolerance else {
                result.append(span)
                continue
            }
            let trimmed = try span.curve.trimmed(
                from: lower,
                to: parameter,
                tolerance: tolerance
            )
            result.append(try ExactBSplineCurveSpan(
                curve: trimmed,
                tolerance: tolerance
            ))
            guard result.last?.endPoint.isApproximatelyEqual(
                to: requestedEndPoint,
                tolerance: tolerance.distance
            ) == true else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: result.last.map {
                        ($0.endPoint - requestedEndPoint).length
                    },
                    tolerance: tolerance,
                    message: "Exact sweep path prefix did not terminate at the requested path point."
                )
            }
            return result
        }
        throw KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            tolerance: tolerance,
            message: "Exact sweep path endpoint does not lie on the ordered exact path."
        )
    }

    private func spans(
        curve: Curve3D,
        lower: Double,
        upper: Double
    ) throws -> [ExactBSplineCurveSpan] {
        guard lower.isFinite,
              upper.isFinite,
              upper - lower > tolerance.angle else {
            throw GeometryError.invalidDistance(upper - lower)
        }
        switch curve {
        case .line, .analytic(.line):
            return [try lineSpan(
                from: curve.point(at: lower, tolerance: tolerance),
                to: curve.point(at: upper, tolerance: tolerance)
            )]
        case let .circle(circle):
            return try conicSpans(
                curve: curve,
                center: circle.center,
                lower: lower,
                upper: upper
            )
        case let .analytic(analytic):
            let center: Point3D
            switch analytic {
            case let .circle(value, _, _),
                 let .arc(value, _, _, _, _),
                 let .ellipse(value, _, _, _, _):
                center = value
            case let .hyperbola(curve):
                return try hyperbolaSpans(
                    curve: curve,
                    lower: lower,
                    upper: upper
                )
            case let .parabola(curve):
                return [try parabolaSpan(
                    curve: curve,
                    lower: lower,
                    upper: upper
                )]
            case .line:
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Exact line path dispatch is inconsistent."
                )
            case .planeTorus:
                throw KernelError.unsupportedEvaluation(
                    tolerance: tolerance,
                    message: "A certified plane-torus intersection curve cannot be converted to a rational B-spline span."
                )
            }
            return try conicSpans(
                curve: curve,
                center: center,
                lower: lower,
                upper: upper
            )
        case let .bSpline(spline):
            return try bSplineSpans(
                spline,
                requestedDomain: .closed(lower, upper)
            )
        case let .rigidImage(image):
            return try spans(
                curve: image.source,
                lower: lower,
                upper: upper
            ).map { span in
                try ExactBSplineCurveSpan(
                    curve: image.transform.applying(
                        to: span.curve,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                )
            }
        case let .affineImage(image):
            return try spans(
                curve: image.source,
                lower: lower,
                upper: upper
            ).map { span in
                try ExactBSplineCurveSpan(
                    curve: image.transform.applying(
                        to: span.curve,
                        tolerance: tolerance
                    ),
                    tolerance: tolerance
                )
            }
        case .implicit, .surfaceLift, .certifiedIntersection:
            throw KernelError.unsupportedEvaluation(
                tolerance: tolerance,
                message: "The exact curve representation cannot be converted to a rational B-spline span."
            )
        }
    }

    private func lineSpan(
        from start: Point3D,
        to end: Point3D
    ) throws -> ExactBSplineCurveSpan {
        try ExactBSplineCurveSpan(
            curve: BSplineCurve3D(
                degree: 1,
                knots: [0.0, 0.0, 1.0, 1.0],
                controlPoints: [start, end]
            ),
            tolerance: tolerance
        )
    }

    private func conicSpans(
        curve: Curve3D,
        center: Point3D,
        lower: Double,
        upper: Double
    ) throws -> [ExactBSplineCurveSpan] {
        let sweep = upper - lower
        let count = max(1, Int(ceil(abs(sweep) / (0.5 * Double.pi))))
        return try (0..<count).map { index in
            let start = lower + sweep * Double(index) / Double(count)
            let end = lower + sweep * Double(index + 1) / Double(count)
            let middle = 0.5 * (start + end)
            let weight = cos(0.5 * (end - start))
            guard weight > Double.ulpOfOne else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Exact conic span produced a singular rational weight."
                )
            }
            let middlePoint = try curve.point(
                at: middle,
                tolerance: tolerance
            )
            return try ExactBSplineCurveSpan(
                curve: BSplineCurve3D(
                    degree: 2,
                    knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                    controlPoints: [
                        try curve.point(at: start, tolerance: tolerance),
                        center + (middlePoint - center) / weight,
                        try curve.point(at: end, tolerance: tolerance),
                    ],
                    weights: [1.0, weight, 1.0]
                ),
                tolerance: tolerance
            )
        }
    }

    private func hyperbolaSpans(
        curve: Hyperbola3D,
        lower: Double,
        upper: Double
    ) throws -> [ExactBSplineCurveSpan] {
        let exactCurve = Curve3D.analytic(.hyperbola(curve))
        let span = upper - lower
        let count = max(1, Int(ceil(abs(span))))
        return try (0..<count).map { index in
            let start = lower + span * Double(index) / Double(count)
            let end = lower + span * Double(index + 1) / Double(count)
            let middle = 0.5 * (start + end)
            let weight = cosh(0.5 * (end - start))
            guard weight.isFinite, weight > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: weight,
                    tolerance: tolerance,
                    message: "Exact hyperbola span exceeded finite rational weights."
                )
            }
            let middlePoint = try exactCurve.point(at: middle, tolerance: tolerance)
            return try ExactBSplineCurveSpan(
                curve: BSplineCurve3D(
                    degree: 2,
                    knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                    controlPoints: [
                        try exactCurve.point(at: start, tolerance: tolerance),
                        curve.center + (middlePoint - curve.center) / weight,
                        try exactCurve.point(at: end, tolerance: tolerance),
                    ],
                    weights: [1.0, weight, 1.0]
                ),
                tolerance: tolerance
            )
        }
    }

    private func parabolaSpan(
        curve: Parabola3D,
        lower: Double,
        upper: Double
    ) throws -> ExactBSplineCurveSpan {
        let exactCurve = Curve3D.analytic(.parabola(curve))
        let start = try curve.differentialGeometry(
            at: lower,
            tolerance: tolerance
        )
        let endPoint = try exactCurve.point(at: upper, tolerance: tolerance)
        return try ExactBSplineCurveSpan(
            curve: BSplineCurve3D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    start.position,
                    start.position + start.firstDerivative * (0.5 * (upper - lower)),
                    endPoint,
                ]
            ),
            tolerance: tolerance
        )
    }

    private func bSplineSpans(
        _ source: BSplineCurve3D,
        requestedDomain: ParameterDomain
    ) throws -> [ExactBSplineCurveSpan] {
        try source.validate(tolerance: tolerance)
        guard case let .closed(lower, upper) = requestedDomain else {
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Exact sweep B-spline paths require a bounded trim."
            )
        }
        var breaks = [lower]
        for knot in source.knots where knot > lower + tolerance.distance
            && knot < upper - tolerance.distance {
            if breaks.last.map({ abs($0 - knot) > tolerance.distance }) != false {
                breaks.append(knot)
            }
        }
        breaks.append(upper)
        let start = try source.point(at: lower, tolerance: tolerance)
        let end = try source.point(at: upper, tolerance: tolerance)
        if breaks.count == 2,
           start.isApproximatelyEqual(to: end, tolerance: tolerance.distance) {
            breaks.insert(0.5 * (lower + upper), at: 1)
        }
        return try (0..<(breaks.count - 1)).map { index in
            try ExactBSplineCurveSpan(
                curve: source.trimmed(
                    from: breaks[index],
                    to: breaks[index + 1],
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )
        }
    }

    private func validateClosure(
        _ spans: [ExactBSplineCurveSpan]
    ) throws {
        for index in spans.indices {
            let next = spans[(index + 1) % spans.count]
            guard spans[index].endPoint.isApproximatelyEqual(
                to: next.startPoint,
                tolerance: tolerance.distance
            ) else {
                throw SketchError.openProfile
            }
        }
    }

    private func validatePathContinuity(
        _ spans: [ExactBSplineCurveSpan]
    ) throws {
        guard spans.isEmpty == false else {
            throw FeatureEvaluationError.emptyResult(
                "Exact sweep path has no non-degenerate spans."
            )
        }
        for index in 0..<(spans.count - 1) {
            guard spans[index].endPoint.isApproximatelyEqual(
                to: spans[index + 1].startPoint,
                tolerance: tolerance.distance
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Exact sweep path spans are disconnected."
                )
            }
        }
    }
}
