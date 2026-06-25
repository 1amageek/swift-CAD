import Foundation
import CADCore
import CADIR

public struct EvaluatedCurvePathSample: Sendable, Hashable {
    public var point: Point3D
    public var tangent: Vector3D
    public var distance: Double

    public init(
        point: Point3D,
        tangent: Vector3D,
        distance: Double
    ) {
        self.point = point
        self.tangent = tangent
        self.distance = distance
    }
}

public struct EvaluatedCurvePathEvaluator: Sendable {
    private let tolerance: ModelingTolerance
    private let minimumCircularSegmentCount = 32
    private let maximumCircularSegmentCount = 8_192
    private let maximumSplineSegmentCount = 512

    public init(tolerance: ModelingTolerance = .standard) {
        self.tolerance = tolerance
    }

    public func length(of curve: EvaluatedCurve) throws -> Double {
        try tolerance.validate()
        try curve.validate(tolerance: tolerance)
        if let exactCurve = curve.exactCurve {
            switch exactCurve {
            case .line:
                let (_, _, length) = try finiteLineParameters(for: curve)
                return length
            case .circle(let circle):
                let (_, _, length) = try finiteCircleParameters(for: curve, circle: circle)
                return length
            case .bSpline:
                return try polylineLength(samples(for: curve, distanceFraction: 1.0))
            }
        }
        return try polylineLength(polylineSamples(points: curve.points, distanceFraction: 1.0))
    }

    public func samples(
        for curve: EvaluatedCurve,
        distanceFraction: Double = 1.0
    ) throws -> [EvaluatedCurvePathSample] {
        try tolerance.validate()
        try curve.validate(tolerance: tolerance)
        guard distanceFraction.isFinite,
              distanceFraction > 0.0,
              distanceFraction <= 1.0 else {
            throw FeatureEvaluationError.invalidDistance(distanceFraction)
        }

        if let exactCurve = curve.exactCurve {
            switch exactCurve {
            case .line(let line):
                return try lineSamples(
                    line: line,
                    curve: curve,
                    distanceFraction: distanceFraction
                )
            case .circle(let circle):
                return try circleSamples(
                    circle: circle,
                    curve: curve,
                    distanceFraction: distanceFraction
                )
            case .bSpline(let spline):
                return try bSplineSamples(
                    spline: spline,
                    curve: curve,
                    distanceFraction: distanceFraction
                )
            }
        }

        return try polylineSamples(
            points: curve.points,
            distanceFraction: distanceFraction
        )
    }

    private func lineSamples(
        line: Line3D,
        curve: EvaluatedCurve,
        distanceFraction: Double
    ) throws -> [EvaluatedCurvePathSample] {
        try line.validate(tolerance: tolerance)
        let (start, end, fullLength) = try finiteLineParameters(for: curve)
        let span = end - start
        let targetEnd = start + span * distanceFraction
        let directionSign = span >= 0.0 ? 1.0 : -1.0
        let startPoint = line.origin + line.direction * start
        let endPoint = line.origin + line.direction * targetEnd
        let tangent = line.direction * directionSign
        try tangent.validateUnitLength(tolerance: tolerance)
        let targetLength = fullLength * distanceFraction
        guard targetLength > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(targetLength)
        }
        return [
            EvaluatedCurvePathSample(point: startPoint, tangent: tangent, distance: 0.0),
            EvaluatedCurvePathSample(point: endPoint, tangent: tangent, distance: targetLength),
        ]
    }

    private func circleSamples(
        circle: Circle3D,
        curve: EvaluatedCurve,
        distanceFraction: Double
    ) throws -> [EvaluatedCurvePathSample] {
        try circle.validate(tolerance: tolerance)
        let (start, end, fullLength) = try finiteCircleParameters(for: curve, circle: circle)
        let span = end - start
        let targetSpan = span * distanceFraction
        let segmentCount = circularSegmentCount(radius: circle.radius, angleSpan: abs(targetSpan))
        var samples: [EvaluatedCurvePathSample] = []
        samples.reserveCapacity(segmentCount + 1)
        for index in 0...segmentCount {
            let ratio = Double(index) / Double(segmentCount)
            let parameter = start + targetSpan * ratio
            let geometry = try Curve3D.circle(circle).differentialGeometry(
                at: parameter,
                tolerance: tolerance
            )
            let tangent = geometry.tangent * (targetSpan >= 0.0 ? 1.0 : -1.0)
            try tangent.validateUnitLength(tolerance: tolerance)
            samples.append(EvaluatedCurvePathSample(
                point: geometry.position,
                tangent: tangent,
                distance: fullLength * distanceFraction * ratio
            ))
        }
        return try validateSamples(samples)
    }

    private func bSplineSamples(
        spline: BSplineCurve3D,
        curve: EvaluatedCurve,
        distanceFraction: Double
    ) throws -> [EvaluatedCurvePathSample] {
        try spline.validate(tolerance: tolerance)
        guard case let .closed(start, end) = curve.parameterDomain else {
            return try polylineSamples(
                points: curve.points,
                distanceFraction: distanceFraction
            )
        }
        let span = end - start
        let targetEnd = start + span * distanceFraction
        let segmentCount = max(
            max(
                bSplineSegmentCount(curve: spline, span: targetEnd - start),
                curve.points.count - 1
            ),
            2
        )
        let directionSign = targetEnd >= start ? 1.0 : -1.0
        var samples: [EvaluatedCurvePathSample] = []
        samples.reserveCapacity(segmentCount + 1)
        var previousPoint: Point3D?
        var distance = 0.0
        for index in 0...segmentCount {
            let ratio = Double(index) / Double(segmentCount)
            let parameter = start + (targetEnd - start) * ratio
            let geometry = try Curve3D.bSpline(spline).differentialGeometry(
                at: parameter,
                tolerance: tolerance
            )
            let tangent = geometry.tangent * directionSign
            try tangent.validateUnitLength(tolerance: tolerance)
            if let previousPoint {
                let segmentLength = (geometry.position - previousPoint).length
                guard segmentLength.isFinite else {
                    throw GeometryError.invalidDistance(segmentLength)
                }
                if segmentLength <= tolerance.distance {
                    continue
                }
                distance += segmentLength
            }
            samples.append(EvaluatedCurvePathSample(
                point: geometry.position,
                tangent: tangent,
                distance: distance
            ))
            previousPoint = geometry.position
        }
        return try validateSamples(samples)
    }

    private func polylineSamples(
        points: [Point3D],
        distanceFraction: Double
    ) throws -> [EvaluatedCurvePathSample] {
        guard points.count >= 2 else {
            throw SketchError.unsupportedEntity("Curve path sampling requires at least two points.")
        }
        for point in points {
            try point.validate()
        }
        var segmentLengths: [Double] = []
        segmentLengths.reserveCapacity(points.count - 1)
        var totalLength = 0.0
        for index in 0..<(points.count - 1) {
            let length = (points[index + 1] - points[index]).length
            guard length.isFinite,
                  length > tolerance.distance else {
                throw SketchError.unsupportedEntity("Curve path contains a degenerate span.")
            }
            segmentLengths.append(length)
            totalLength += length
        }
        guard totalLength > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(totalLength)
        }

        let targetDistance = totalLength * distanceFraction
        var sampledPoints = [points[0]]
        var distances = [0.0]
        var coveredDistance = 0.0
        for index in segmentLengths.indices {
            let start = points[index]
            let end = points[index + 1]
            let segmentLength = segmentLengths[index]
            let remainingDistance = targetDistance - coveredDistance
            if remainingDistance >= segmentLength - tolerance.distance {
                coveredDistance += segmentLength
                append(end, distance: coveredDistance, points: &sampledPoints, distances: &distances)
                continue
            }

            guard remainingDistance > tolerance.distance else {
                break
            }
            let direction = try (end - start).normalized(tolerance: tolerance.distance)
            append(
                start + direction * remainingDistance,
                distance: targetDistance,
                points: &sampledPoints,
                distances: &distances
            )
            break
        }

        guard sampledPoints.count >= 2 else {
            throw FeatureEvaluationError.invalidDistance(targetDistance)
        }
        var samples: [EvaluatedCurvePathSample] = []
        samples.reserveCapacity(sampledPoints.count)
        for index in sampledPoints.indices {
            samples.append(EvaluatedCurvePathSample(
                point: sampledPoints[index],
                tangent: try polylineTangent(at: index, points: sampledPoints),
                distance: distances[index]
            ))
        }
        return try validateSamples(samples)
    }

    private func finiteLineParameters(for curve: EvaluatedCurve) throws -> (Double, Double, Double) {
        guard case let .closed(start, end) = curve.parameterDomain else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Line curve path evaluation requires a finite parameter range."
            )
        }
        let length = abs(end - start)
        guard length > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(length)
        }
        return (start, end, length)
    }

    private func finiteCircleParameters(
        for curve: EvaluatedCurve,
        circle: Circle3D
    ) throws -> (Double, Double, Double) {
        try circle.validate(tolerance: tolerance)
        let start: Double
        let end: Double
        switch curve.parameterDomain {
        case let .closed(lower, upper):
            start = lower
            end = upper
        case .periodic(let period):
            guard curve.isClosed,
                  let first = curve.points.first else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Periodic circle curve path evaluation requires a closed evaluated curve."
                )
            }
            start = try circleParameter(for: first, on: circle)
            end = start + period
        case .unbounded:
            throw FeatureEvaluationError.unsupportedOperation(
                "Circle curve path evaluation requires a finite parameter range."
            )
        }
        let length = circle.radius * abs(end - start)
        guard length > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(length)
        }
        return (start, end, length)
    }

    private func circleParameter(
        for point: Point3D,
        on circle: Circle3D
    ) throws -> Double {
        let (u, v) = try circleBasis(for: circle)
        let offset = point - circle.center
        return atan2(offset.dot(v), offset.dot(u))
    }

    private func circleBasis(for circle: Circle3D) throws -> (Vector3D, Vector3D) {
        let normal = try circle.normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
        let v = normal.cross(u)
        return (u, v)
    }

    private func circularSegmentCount(radius: Double, angleSpan: Double) -> Int {
        let ratio = min(max(tolerance.distance / radius, 1.0e-9), 0.5)
        let angle = 2.0 * acos(1.0 - ratio)
        let requiredFullCircleCount = Int(ceil((Double.pi * 2.0) / angle))
        let fullCircleCount = min(
            max(requiredFullCircleCount, minimumCircularSegmentCount),
            maximumCircularSegmentCount
        )
        let proportionalCount = Int(ceil(Double(fullCircleCount) * angleSpan / (Double.pi * 2.0)))
        return max(proportionalCount, 2)
    }

    private func bSplineSegmentCount(curve: BSplineCurve3D, span: Double) -> Int {
        let domainLength: Double
        switch curve.domain {
        case let .closed(lower, upper):
            domainLength = max(upper - lower, Double.ulpOfOne)
        case .unbounded, .periodic:
            domainLength = max(abs(span), Double.ulpOfOne)
        }
        let spanFraction = min(max(abs(span) / domainLength, 0.0), 1.0)
        let controlLength = controlPolygonLength(curve.controlPoints) * max(spanFraction, Double.ulpOfOne)
        let toleranceLimit = max(4, Int(ceil(sqrt(controlLength / tolerance.distance))))
        return min(toleranceLimit, maximumSplineSegmentCount)
    }

    private func controlPolygonLength(_ points: [Point3D]) -> Double {
        guard points.count > 1 else {
            return 0.0
        }
        var length = 0.0
        for index in 1..<points.count {
            length += (points[index] - points[index - 1]).length
        }
        return length
    }

    private func polylineLength(_ samples: [EvaluatedCurvePathSample]) throws -> Double {
        guard let length = samples.last?.distance,
              length.isFinite,
              length > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(samples.last?.distance ?? 0.0)
        }
        return length
    }

    private func append(
        _ point: Point3D,
        distance: Double,
        points: inout [Point3D],
        distances: inout [Double]
    ) {
        if let last = points.last,
           last.isApproximatelyEqual(to: point, tolerance: tolerance.distance) {
            distances[distances.count - 1] = distance
            return
        }
        points.append(point)
        distances.append(distance)
    }

    private func polylineTangent(at index: Int, points: [Point3D]) throws -> Vector3D {
        if index == points.startIndex {
            return try (points[index + 1] - points[index]).normalized(tolerance: tolerance.distance)
        }
        if index == points.index(before: points.endIndex) {
            return try (points[index] - points[index - 1]).normalized(tolerance: tolerance.distance)
        }
        return try (points[index + 1] - points[index - 1]).normalized(tolerance: tolerance.distance)
    }

    private func validateSamples(
        _ samples: [EvaluatedCurvePathSample]
    ) throws -> [EvaluatedCurvePathSample] {
        guard samples.count >= 2 else {
            throw FeatureEvaluationError.invalidDistance(samples.last?.distance ?? 0.0)
        }
        var previousDistance = samples[0].distance
        guard abs(previousDistance) <= tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(previousDistance)
        }
        for sample in samples {
            try sample.point.validate()
            try sample.tangent.validateUnitLength(tolerance: tolerance)
            guard sample.distance.isFinite,
                  sample.distance + tolerance.distance >= previousDistance else {
                throw FeatureEvaluationError.invalidDistance(sample.distance)
            }
            previousDistance = sample.distance
        }
        guard let totalLength = samples.last?.distance,
              totalLength > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(samples.last?.distance ?? 0.0)
        }
        return samples
    }
}
