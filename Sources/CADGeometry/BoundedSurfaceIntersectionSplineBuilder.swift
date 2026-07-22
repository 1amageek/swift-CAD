import Foundation
import CADCore

struct BoundedSurfaceIntersectionSplineBuilder {
    struct Sample: Sendable {
        let point: Point3D
        let firstParameter: Point2D
        let secondParameter: Point2D
        let residual: Double
        let pointDerivative: Vector3D?
        let firstParameterDerivative: Point2D?
        let secondParameterDerivative: Point2D?
    }

    struct Result: Sendable {
        let curve: Curve3D
        let firstPcurve: SurfaceParameterCurve
        let secondPcurve: SurfaceParameterCurve
        let maximumResidual: Double
    }

    func build(
        samples: [Sample],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> Result {
        guard samples.count >= 2 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A bounded surface intersection spline requires at least two samples."
            )
        }
        let parameters = try chordParameters(samples: samples, tolerance: tolerance)
        let firstSample = samples[0]
        let lastSample = samples[samples.count - 1]
        let isClosed = (firstSample.point - lastSample.point).length <= tolerance.distance
            && parameterDistance(
                firstSample.firstParameter,
                lastSample.firstParameter
            ) <= tolerance.relative
            && parameterDistance(
                firstSample.secondParameter,
                lastSample.secondParameter
            ) <= tolerance.relative
        let suppliedPointDerivatives = samples.compactMap(\.pointDerivative)
        let suppliedFirstDerivatives = samples.compactMap(\.firstParameterDerivative)
        let suppliedSecondDerivatives = samples.compactMap(\.secondParameterDerivative)
        let hasSuppliedDerivatives = suppliedPointDerivatives.count == samples.count
            && suppliedFirstDerivatives.count == samples.count
            && suppliedSecondDerivatives.count == samples.count
        let unboundedPointDerivatives = hasSuppliedDerivatives
            ? suppliedPointDerivatives
            : pointDerivatives(
                samples: samples,
                parameters: parameters,
                isClosed: isClosed,
                tolerance: tolerance
            )
        let unboundedFirstDerivatives = hasSuppliedDerivatives
            ? suppliedFirstDerivatives
            : parameterDerivatives(
                samples.map(\.firstParameter),
                points: samples.map(\.point),
                parameters: parameters,
                isClosed: isClosed
            )
        let unboundedSecondDerivatives = hasSuppliedDerivatives
            ? suppliedSecondDerivatives
            : parameterDerivatives(
                samples.map(\.secondParameter),
                points: samples.map(\.point),
                parameters: parameters,
                isClosed: isClosed
            )
        let boundedDerivatives = parameterDomainBoundedDerivatives(
            samples: samples,
            parameters: parameters,
            pointDerivatives: unboundedPointDerivatives,
            firstDerivatives: unboundedFirstDerivatives,
            secondDerivatives: unboundedSecondDerivatives,
            first: first,
            second: second
        )
        let pointDerivatives = boundedDerivatives.point
        let firstDerivatives = boundedDerivatives.first
        let secondDerivatives = boundedDerivatives.second
        var pointSegments: [[Point3D]] = []
        var firstSegments: [[Point2D]] = []
        var secondSegments: [[Point2D]] = []
        var maximumResidual = samples.map(\.residual).max() ?? 0.0
        for index in 1..<samples.count {
            let span = parameters[index] - parameters[index - 1]
            let pointControls = pointControls(
                lower: samples[index - 1].point,
                upper: samples[index].point,
                lowerDerivative: pointDerivatives[index - 1],
                upperDerivative: pointDerivatives[index],
                span: span
            )
            let firstControls = parameterControls(
                lower: samples[index - 1].firstParameter,
                upper: samples[index].firstParameter,
                lowerDerivative: firstDerivatives[index - 1],
                upperDerivative: firstDerivatives[index],
                span: span
            )
            let secondControls = parameterControls(
                lower: samples[index - 1].secondParameter,
                upper: samples[index].secondParameter,
                lowerDerivative: secondDerivatives[index - 1],
                upperDerivative: secondDerivatives[index],
                span: span
            )
            pointSegments.append(pointControls)
            firstSegments.append(firstControls)
            secondSegments.append(secondControls)
        }
        maximumResidual = max(
            maximumResidual,
            try verifiedResidual(
                pointSegments: pointSegments,
                firstSegments: firstSegments,
                secondSegments: secondSegments,
                first: first,
                second: second,
                options: options,
                tolerance: tolerance
            )
        )
        guard maximumResidual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "Composite cubic surface intersection failed residual certification."
            )
        }
        let knots = compositeKnots(parameters: parameters)
        let curve = BSplineCurve3D(
            degree: 3,
            knots: knots,
            controlPoints: compositePoints(pointSegments)
        )
        let firstPcurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 3,
            knots: knots,
            controlPoints: compositePoints(firstSegments)
        ))
        let secondPcurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 3,
            knots: knots,
            controlPoints: compositePoints(secondSegments)
        ))
        try curve.validate(tolerance: tolerance)
        try firstPcurve.validate(on: firstSurface, tolerance: tolerance)
        try secondPcurve.validate(on: secondSurface, tolerance: tolerance)
        return Result(
            curve: .bSpline(curve),
            firstPcurve: firstPcurve,
            secondPcurve: secondPcurve,
            maximumResidual: maximumResidual
        )
    }

    private func chordParameters(
        samples: [Sample],
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        var result = [0.0]
        for index in 1..<samples.count {
            let distance = (samples[index].point - samples[index - 1].point).length
            guard distance > tolerance.distance * 0.05 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    residual: distance,
                    tolerance: tolerance,
                    message: "Adjacent surface intersection samples are not geometrically distinct."
                )
            }
            result.append((result.last ?? 0.0) + distance)
        }
        return result
    }

    private func pointDerivatives(
        samples: [Sample],
        parameters: [Double],
        isClosed: Bool,
        tolerance: ModelingTolerance
    ) -> [Vector3D] {
        var result: [Vector3D] = []
        for index in samples.indices {
            if index == 0 {
                result.append(
                    (samples[1].point - samples[0].point)
                        / (parameters[1] - parameters[0])
                )
            } else if index == samples.count - 1 {
                result.append(
                    (samples[index].point - samples[index - 1].point)
                        / (parameters[index] - parameters[index - 1])
                )
            } else {
                result.append(
                    (samples[index + 1].point - samples[index - 1].point)
                        / (parameters[index + 1] - parameters[index - 1])
                )
            }
        }
        if isClosed,
           let incoming = result.last,
           let outgoing = result.first {
            let sum = incoming + outgoing
            if sum.length > tolerance.relative {
                let magnitude = (incoming.length + outgoing.length) * 0.5
                let blended = sum / sum.length * magnitude
                result[0] = blended
                result[result.count - 1] = blended
            }
        }
        return result
    }

    private func parameterDerivatives(
        _ values: [Point2D],
        points: [Point3D],
        parameters: [Double],
        isClosed: Bool
    ) -> [Point2D] {
        var result = values.indices.map { index in
            if index == 0 {
                return quotient(values[1], values[0], by: parameters[1] - parameters[0])
            }
            if index == values.count - 1 {
                return quotient(
                    values[index],
                    values[index - 1],
                    by: parameters[index] - parameters[index - 1]
                )
            }
            let incoming = (points[index] - points[index - 1]).length
            let outgoing = (points[index + 1] - points[index]).length
            let incomingDerivative = quotient(
                values[index],
                values[index - 1],
                by: parameters[index] - parameters[index - 1]
            )
            let outgoingDerivative = quotient(
                values[index + 1],
                values[index],
                by: parameters[index + 1] - parameters[index]
            )
            let total = incoming + outgoing
            return Point2D(
                x: (incomingDerivative.x * outgoing + outgoingDerivative.x * incoming) / total,
                y: (incomingDerivative.y * outgoing + outgoingDerivative.y * incoming) / total
            )
        }
        if isClosed,
           let incoming = result.last,
           let outgoing = result.first {
            let blended = Point2D(
                x: (incoming.x + outgoing.x) * 0.5,
                y: (incoming.y + outgoing.y) * 0.5
            )
            result[0] = blended
            result[result.count - 1] = blended
        }
        return result
    }

    private func pointControls(
        lower: Point3D,
        upper: Point3D,
        lowerDerivative: Vector3D,
        upperDerivative: Vector3D,
        span: Double
    ) -> [Point3D] {
        [
            lower,
            lower + lowerDerivative * (span / 3.0),
            upper + upperDerivative * (-span / 3.0),
            upper,
        ]
    }

    private func parameterDomainBoundedDerivatives(
        samples: [Sample],
        parameters: [Double],
        pointDerivatives: [Vector3D],
        firstDerivatives: [Point2D],
        secondDerivatives: [Point2D],
        first: BSplineSurface3D,
        second: BSplineSurface3D
    ) -> (point: [Vector3D], first: [Point2D], second: [Point2D]) {
        let firstU = closedBounds(first.uDomain)
        let firstV = closedBounds(first.vDomain)
        let secondU = closedBounds(second.uDomain)
        let secondV = closedBounds(second.vDomain)
        var boundedPoints: [Vector3D] = []
        var boundedFirst: [Point2D] = []
        var boundedSecond: [Point2D] = []
        boundedPoints.reserveCapacity(samples.count)
        boundedFirst.reserveCapacity(samples.count)
        boundedSecond.reserveCapacity(samples.count)
        for index in samples.indices {
            var scale = 1.0
            if index > 0 {
                let span = parameters[index] - parameters[index - 1]
                scale = min(
                    scale,
                    parameterDerivativeScale(
                        sample: samples[index],
                        firstDerivative: firstDerivatives[index],
                        secondDerivative: secondDerivatives[index],
                        signedControlSpan: -span / 3.0,
                        firstU: firstU,
                        firstV: firstV,
                        secondU: secondU,
                        secondV: secondV
                    )
                )
            }
            if index + 1 < samples.count {
                let span = parameters[index + 1] - parameters[index]
                scale = min(
                    scale,
                    parameterDerivativeScale(
                        sample: samples[index],
                        firstDerivative: firstDerivatives[index],
                        secondDerivative: secondDerivatives[index],
                        signedControlSpan: span / 3.0,
                        firstU: firstU,
                        firstV: firstV,
                        secondU: secondU,
                        secondV: secondV
                    )
                )
            }
            let boundedScale = scale < 1.0
                ? max(scale.nextDown, 0.0)
                : 1.0
            boundedPoints.append(pointDerivatives[index] * boundedScale)
            boundedFirst.append(scaled(firstDerivatives[index], by: boundedScale))
            boundedSecond.append(scaled(secondDerivatives[index], by: boundedScale))
        }
        return (boundedPoints, boundedFirst, boundedSecond)
    }

    private func parameterDerivativeScale(
        sample: Sample,
        firstDerivative: Point2D,
        secondDerivative: Point2D,
        signedControlSpan: Double,
        firstU: (lower: Double, upper: Double),
        firstV: (lower: Double, upper: Double),
        secondU: (lower: Double, upper: Double),
        secondV: (lower: Double, upper: Double)
    ) -> Double {
        let values = [
            sample.firstParameter.x,
            sample.firstParameter.y,
            sample.secondParameter.x,
            sample.secondParameter.y,
        ]
        let changes = [
            firstDerivative.x * signedControlSpan,
            firstDerivative.y * signedControlSpan,
            secondDerivative.x * signedControlSpan,
            secondDerivative.y * signedControlSpan,
        ]
        let bounds = [firstU, firstV, secondU, secondV]
        return values.indices.reduce(1.0) { scale, index in
            let change = changes[index]
            if change > 0.0 {
                return min(
                    scale,
                    max(bounds[index].upper - values[index], 0.0) / change
                )
            }
            if change < 0.0 {
                return min(
                    scale,
                    max(values[index] - bounds[index].lower, 0.0) / -change
                )
            }
            return scale
        }
    }

    private func scaled(_ value: Point2D, by scale: Double) -> Point2D {
        Point2D(x: value.x * scale, y: value.y * scale)
    }

    private func closedBounds(
        _ domain: ParameterDomain
    ) -> (lower: Double, upper: Double) {
        switch domain {
        case let .closed(lower, upper):
            return (lower, upper)
        case .periodic, .unbounded:
            return (0.0, 0.0)
        }
    }

    private func parameterControls(
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

    private func verifiedResidual(
        pointSegments: [[Point3D]],
        firstSegments: [[Point2D]],
        secondSegments: [[Point2D]],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let segments = pointSegments.indices.map { index in
            CubicSurfaceResidualCertifier.Segment(
                pointControls: pointSegments[index],
                firstControls: firstSegments[index],
                secondControls: secondSegments[index]
            )
        }
        return try CubicSurfaceResidualCertifier().certify(
            segments: segments,
            first: first,
            second: second,
            options: options,
            tolerance: tolerance
        ).maximumResidualUpperBound
    }

    private func compositeKnots(parameters: [Double]) -> [Double] {
        guard let first = parameters.first,
              let last = parameters.last else { return [] }
        return Array(repeating: first, count: 4)
            + parameters.dropFirst().dropLast().flatMap {
                Array(repeating: $0, count: 3)
            }
            + Array(repeating: last, count: 4)
    }

    private func compositePoints<T>(_ segments: [[T]]) -> [T] {
        guard let first = segments.first else { return [] }
        return segments.dropFirst().reduce(into: first) { result, segment in
            result.append(contentsOf: segment.dropFirst())
        }
    }

    private func quotient(_ upper: Point2D, _ lower: Point2D, by divisor: Double) -> Point2D {
        Point2D(
            x: (upper.x - lower.x) / divisor,
            y: (upper.y - lower.y) / divisor
        )
    }

    private func parameterDistance(_ first: Point2D, _ second: Point2D) -> Double {
        hypot(first.x - second.x, first.y - second.y)
    }

}
