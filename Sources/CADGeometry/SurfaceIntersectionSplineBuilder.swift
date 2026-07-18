import Foundation
import CADCore

struct SurfaceIntersectionSplineBuilder {
    private struct Sample {
        let parameter: Double
        let point: Point3D
        let firstUV: Point2D
        let secondUV: Point2D
        let maximumProjectionResidual: Double
    }

    private struct Derivatives {
        let point: Vector3D
        let firstUV: Point2D
        let secondUV: Point2D
    }

    private struct Segment {
        let lower: Double
        let upper: Double
        let points: [Point3D]
        let firstParameters: [Point2D]
        let secondParameters: [Point2D]
        let maximumResidual: Double
    }

    private let firstSurface: Surface3D
    private let secondSurface: Surface3D
    private let options: SurfaceSurfaceIntersectionOptions
    private let tolerance: ModelingTolerance

    init(
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) {
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        self.options = options
        self.tolerance = tolerance
    }

    func intersection(
        parameterRange: ClosedRange<Double>,
        initialBreaks: [Double],
        kind: CurveSurfaceIntersectionKind,
        isClosed: Bool = true,
        pointAt: (Double) throws -> Point3D
    ) throws -> SurfaceSurfaceIntersection {
        let breaks = try validatedBreaks(initialBreaks, parameterRange: parameterRange)
        guard breaks.count - 1 <= options.maximumSeedCount else {
            throw resourceLimit(
                message: "Surface intersection initial trace exceeded its segment limit."
            )
        }

        var samples: [Sample] = []
        samples.reserveCapacity(breaks.count)
        for parameter in breaks {
            samples.append(try sample(
                at: parameter,
                firstReference: samples.last?.firstUV,
                secondReference: samples.last?.secondUV,
                pointAt: pointAt
            ))
        }

        var remainingSegments = options.maximumSeedCount
        var segments: [Segment] = []
        for index in 1..<samples.count {
            try refine(
                lower: samples[index - 1],
                upper: samples[index],
                parameterRange: parameterRange,
                isClosed: isClosed,
                depth: 0,
                pointAt: pointAt,
                remainingSegments: &remainingSegments,
                result: &segments
            )
        }
        guard segments.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Adaptive surface intersection tracing produced no curve segments."
            )
        }
        return try makeIntersection(
            segments: segments,
            kind: kind,
            pointAt: pointAt
        )
    }

    private func refine(
        lower: Sample,
        upper: Sample,
        parameterRange: ClosedRange<Double>,
        isClosed: Bool,
        depth: Int,
        pointAt: (Double) throws -> Point3D,
        remainingSegments: inout Int,
        result: inout [Segment]
    ) throws {
        let segment = try cubicSegment(
            lower: lower,
            upper: upper,
            parameterRange: parameterRange,
            isClosed: isClosed,
            pointAt: pointAt
        )
        if segment.maximumResidual <= tolerance.distance * 0.5 {
            guard remainingSegments > 0 else {
                throw resourceLimit(
                    residual: segment.maximumResidual,
                    message: "Adaptive surface intersection trace exceeded its segment limit."
                )
            }
            remainingSegments -= 1
            result.append(segment)
            return
        }
        guard depth < options.maximumSubdivisionDepth else {
            throw resourceLimit(
                residual: segment.maximumResidual,
                message: "Adaptive surface intersection trace exceeded its subdivision limit."
            )
        }
        let middleParameter = lower.parameter + (upper.parameter - lower.parameter) * 0.5
        let middle = try sample(
            at: middleParameter,
            firstReference: midpoint(lower.firstUV, upper.firstUV),
            secondReference: midpoint(lower.secondUV, upper.secondUV),
            pointAt: pointAt
        )
        try refine(
            lower: lower,
            upper: middle,
            parameterRange: parameterRange,
            isClosed: isClosed,
            depth: depth + 1,
            pointAt: pointAt,
            remainingSegments: &remainingSegments,
            result: &result
        )
        try refine(
            lower: middle,
            upper: upper,
            parameterRange: parameterRange,
            isClosed: isClosed,
            depth: depth + 1,
            pointAt: pointAt,
            remainingSegments: &remainingSegments,
            result: &result
        )
    }

    private func cubicSegment(
        lower: Sample,
        upper: Sample,
        parameterRange: ClosedRange<Double>,
        isClosed: Bool,
        pointAt: (Double) throws -> Point3D
    ) throws -> Segment {
        let span = upper.parameter - lower.parameter
        guard span > tolerance.angle else {
            throw GeometryError.invalidDistance(span)
        }
        let lowerDerivative = try derivatives(
            at: lower,
            parameterRange: parameterRange,
            isClosed: isClosed,
            pointAt: pointAt
        )
        let upperDerivative = try derivatives(
            at: upper,
            parameterRange: parameterRange,
            isClosed: isClosed,
            pointAt: pointAt
        )
        let points = [
            lower.point,
            lower.point + lowerDerivative.point * (span / 3.0),
            upper.point + upperDerivative.point * (-span / 3.0),
            upper.point,
        ]
        let firstParameters = cubicControls(
            lower: lower.firstUV,
            upper: upper.firstUV,
            lowerDerivative: lowerDerivative.firstUV,
            upperDerivative: upperDerivative.firstUV,
            span: span
        )
        let secondParameters = cubicControls(
            lower: lower.secondUV,
            upper: upper.secondUV,
            lowerDerivative: lowerDerivative.secondUV,
            upperDerivative: upperDerivative.secondUV,
            span: span
        )

        var maximumResidual = max(
            lower.maximumProjectionResidual,
            upper.maximumProjectionResidual
        )
        for fraction in [0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875] {
            let parameter = lower.parameter + span * fraction
            let curvePoint = cubicPoint(points, fraction: fraction)
            let firstUV = cubicPoint(firstParameters, fraction: fraction)
            let secondUV = cubicPoint(secondParameters, fraction: fraction)
            let firstPoint = try firstSurface.point(
                u: firstUV.x,
                v: firstUV.y,
                tolerance: tolerance
            )
            let secondPoint = try secondSurface.point(
                u: secondUV.x,
                v: secondUV.y,
                tolerance: tolerance
            )
            let exactPoint = try pointAt(parameter)
            maximumResidual = max(
                maximumResidual,
                (curvePoint - firstPoint).length,
                (curvePoint - secondPoint).length,
                (curvePoint - exactPoint).length,
                (firstPoint - secondPoint).length
            )
        }
        return Segment(
            lower: lower.parameter,
            upper: upper.parameter,
            points: points,
            firstParameters: firstParameters,
            secondParameters: secondParameters,
            maximumResidual: maximumResidual
        )
    }

    private func derivatives(
        at centerSample: Sample,
        parameterRange: ClosedRange<Double>,
        isClosed: Bool,
        pointAt: (Double) throws -> Point3D
    ) throws -> Derivatives {
        let rangeLength = parameterRange.upperBound - parameterRange.lowerBound
        let centralDifferenceScale = pow(Double.ulpOfOne, 1.0 / 3.0)
        let step = max(
            rangeLength * centralDifferenceScale,
            tolerance.angle * 16.0
        )
        let lowerParameter = isClosed
            ? wrapped(centerSample.parameter - step, parameterRange: parameterRange)
            : max(parameterRange.lowerBound, centerSample.parameter - step)
        let upperParameter = isClosed
            ? wrapped(centerSample.parameter + step, parameterRange: parameterRange)
            : min(parameterRange.upperBound, centerSample.parameter + step)
        let lower = try sample(
            at: lowerParameter,
            firstReference: centerSample.firstUV,
            secondReference: centerSample.secondUV,
            pointAt: pointAt
        )
        let upper = try sample(
            at: upperParameter,
            firstReference: centerSample.firstUV,
            secondReference: centerSample.secondUV,
            pointAt: pointAt
        )
        let denominator = isClosed ? 2.0 * step : upperParameter - lowerParameter
        guard denominator > tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: denominator,
                tolerance: tolerance,
                message: "Surface intersection derivative interval collapsed."
            )
        }
        return Derivatives(
            point: (upper.point - lower.point) / denominator,
            firstUV: Point2D(
                x: (upper.firstUV.x - lower.firstUV.x) / denominator,
                y: (upper.firstUV.y - lower.firstUV.y) / denominator
            ),
            secondUV: Point2D(
                x: (upper.secondUV.x - lower.secondUV.x) / denominator,
                y: (upper.secondUV.y - lower.secondUV.y) / denominator
            )
        )
    }

    private func sample(
        at parameter: Double,
        firstReference: Point2D?,
        secondReference: Point2D?,
        pointAt: (Double) throws -> Point3D
    ) throws -> Sample {
        let point = try pointAt(parameter)
        let firstProjection = try firstSurface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        let secondProjection = try secondSurface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        return Sample(
            parameter: parameter,
            point: point,
            firstUV: Point2D(
                x: unwrapped(
                    firstProjection.u,
                    domain: firstSurface.uDomain,
                    reference: firstReference?.x
                ),
                y: unwrapped(
                    firstProjection.v,
                    domain: firstSurface.vDomain,
                    reference: firstReference?.y
                )
            ),
            secondUV: Point2D(
                x: unwrapped(
                    secondProjection.u,
                    domain: secondSurface.uDomain,
                    reference: secondReference?.x
                ),
                y: unwrapped(
                    secondProjection.v,
                    domain: secondSurface.vDomain,
                    reference: secondReference?.y
                )
            ),
            maximumProjectionResidual: max(
                firstProjection.residual,
                secondProjection.residual
            )
        )
    }

    private func makeIntersection(
        segments: [Segment],
        kind: CurveSurfaceIntersectionKind,
        pointAt: (Double) throws -> Point3D
    ) throws -> SurfaceSurfaceIntersection {
        let curve = BSplineCurve3D(
            degree: 3,
            knots: compositeKnots(segments: segments),
            controlPoints: compositePoints(segments.map(\.points))
        )
        let firstParameterCurve = BSplineCurve2D(
            degree: 3,
            knots: compositeKnots(segments: segments),
            controlPoints: compositePoints(segments.map(\.firstParameters))
        )
        let secondParameterCurve = BSplineCurve2D(
            degree: 3,
            knots: compositeKnots(segments: segments),
            controlPoints: compositePoints(segments.map(\.secondParameters))
        )
        try curve.validate(tolerance: tolerance)
        let firstPcurve = SurfaceParameterCurve.bSpline(firstParameterCurve)
        let secondPcurve = SurfaceParameterCurve.bSpline(secondParameterCurve)
        try firstPcurve.validate(on: firstSurface, tolerance: tolerance)
        try secondPcurve.validate(on: secondSurface, tolerance: tolerance)

        let anchorPoint = try pointAt(segments[0].lower)
        let firstAnchor = try firstSurface.parameterProjection(
            of: anchorPoint,
            tolerance: tolerance
        )
        let secondAnchor = try secondSurface.parameterProjection(
            of: anchorPoint,
            tolerance: tolerance
        )
        return .curve(try SurfaceSurfaceIntersectionCurve(
            curve: .bSpline(curve),
            kind: kind,
            firstSurfaceParameterCurve: firstPcurve,
            secondSurfaceParameterCurve: secondPcurve,
            firstSurfaceAnchor: firstAnchor,
            secondSurfaceAnchor: secondAnchor,
            maximumResidual: segments.map(\.maximumResidual).max() ?? 0.0,
            tolerance: tolerance
        ))
    }

    private func validatedBreaks(
        _ values: [Double],
        parameterRange: ClosedRange<Double>
    ) throws -> [Double] {
        let lower = parameterRange.lowerBound
        let upper = parameterRange.upperBound
        guard lower.isFinite,
              upper.isFinite,
              upper - lower > tolerance.angle else {
            throw GeometryError.invalidDistance(upper - lower)
        }
        var sorted = values
            .filter { $0.isFinite && $0 >= lower && $0 <= upper }
            .sorted()
        sorted.append(contentsOf: [lower, upper])
        sorted.sort()
        var result: [Double] = []
        for value in sorted {
            if result.last.map({ abs($0 - value) <= tolerance.angle }) != true {
                result.append(value)
            }
        }
        guard result.count >= 2,
              abs((result.first ?? lower) - lower) <= tolerance.angle,
              abs((result.last ?? upper) - upper) <= tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Surface intersection trace requires both parameter boundaries."
            )
        }
        return result
    }

    private func compositeKnots(segments: [Segment]) -> [Double] {
        guard let first = segments.first, let last = segments.last else { return [] }
        var knots = Array(repeating: first.lower, count: 4)
        for segment in segments.dropLast() {
            knots.append(contentsOf: Array(repeating: segment.upper, count: 3))
        }
        knots.append(contentsOf: Array(repeating: last.upper, count: 4))
        return knots
    }

    private func compositePoints<T>(_ segments: [[T]]) -> [T] {
        guard let first = segments.first else { return [] }
        var result = first
        for segment in segments.dropFirst() {
            result.append(contentsOf: segment.dropFirst())
        }
        return result
    }

    private func cubicControls(
        lower: Point2D,
        upper: Point2D,
        lowerDerivative: Point2D,
        upperDerivative: Point2D,
        span: Double
    ) -> [Point2D] {
        [
            lower,
            Point2D(
                x: lower.x + lowerDerivative.x * span / 3.0,
                y: lower.y + lowerDerivative.y * span / 3.0
            ),
            Point2D(
                x: upper.x - upperDerivative.x * span / 3.0,
                y: upper.y - upperDerivative.y * span / 3.0
            ),
            upper,
        ]
    }

    private func cubicPoint(_ controls: [Point3D], fraction: Double) -> Point3D {
        let weights = cubicWeights(fraction: fraction)
        return Point3D(
            x: controls[0].x * weights[0]
                + controls[1].x * weights[1]
                + controls[2].x * weights[2]
                + controls[3].x * weights[3],
            y: controls[0].y * weights[0]
                + controls[1].y * weights[1]
                + controls[2].y * weights[2]
                + controls[3].y * weights[3],
            z: controls[0].z * weights[0]
                + controls[1].z * weights[1]
                + controls[2].z * weights[2]
                + controls[3].z * weights[3]
        )
    }

    private func cubicPoint(_ controls: [Point2D], fraction: Double) -> Point2D {
        let weights = cubicWeights(fraction: fraction)
        return Point2D(
            x: controls[0].x * weights[0]
                + controls[1].x * weights[1]
                + controls[2].x * weights[2]
                + controls[3].x * weights[3],
            y: controls[0].y * weights[0]
                + controls[1].y * weights[1]
                + controls[2].y * weights[2]
                + controls[3].y * weights[3]
        )
    }

    private func cubicWeights(fraction: Double) -> [Double] {
        let complement = 1.0 - fraction
        return [
            complement * complement * complement,
            3.0 * complement * complement * fraction,
            3.0 * complement * fraction * fraction,
            fraction * fraction * fraction,
        ]
    }

    private func midpoint(_ first: Point2D, _ second: Point2D) -> Point2D {
        Point2D(
            x: (first.x + second.x) * 0.5,
            y: (first.y + second.y) * 0.5
        )
    }

    private func wrapped(
        _ parameter: Double,
        parameterRange: ClosedRange<Double>
    ) -> Double {
        let lower = parameterRange.lowerBound
        let length = parameterRange.upperBound - lower
        let remainder = (parameter - lower).truncatingRemainder(dividingBy: length)
        return lower + (remainder >= 0.0 ? remainder : remainder + length)
    }

    private func unwrapped(
        _ value: Double,
        domain: ParameterDomain,
        reference: Double?
    ) -> Double {
        guard case let .periodic(period) = domain,
              let reference else {
            return value
        }
        return value + ((reference - value) / period).rounded() * period
    }

    private func resourceLimit(
        residual: Double? = nil,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
