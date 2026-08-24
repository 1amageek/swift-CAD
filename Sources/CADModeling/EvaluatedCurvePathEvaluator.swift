import Foundation
import CADCore
import CADGeometry
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
    private struct PreparedPathSegment {
        let segment: EvaluatedCurvePathSegment
        let path: PreparedEvaluatedCurvePath

        var length: Double {
            path.totalLength
        }
    }

    private let tolerance: ModelingTolerance
    private let arcLengthResolver: any CurveArcLengthResolving
    private let minimumCircularSegmentCount = 32
    private let maximumCircularSegmentCount = 8_192
    private let maximumSplineSegmentCount = 512

    public init(
        tolerance: ModelingTolerance,
        arcLengthResolver: any CurveArcLengthResolving = DefaultCurveArcLengthResolver()
    ) {
        self.tolerance = tolerance
        self.arcLengthResolver = arcLengthResolver
    }

    /// Prepares a reusable distance parameterization for an evaluated curve.
    /// Exact geometry remains authoritative whenever the curve provides it.
    public func prepare(
        _ curve: EvaluatedCurve
    ) throws -> PreparedEvaluatedCurvePath {
        try tolerance.validate()
        try curve.validate(tolerance: tolerance)
        guard let exactCurve = curve.exactCurve else {
            return try prepare(points: curve.points)
        }
        let interval = try traversalInterval(for: curve, exactCurve: exactCurve)
        let parameterization = try arcLengthResolver.parameterization(
            of: exactCurve,
            over: interval,
            tolerance: tolerance
        )
        let totalLength = parameterization.lengthEnclosure.midpoint
        guard totalLength.isFinite,
              totalLength > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(totalLength)
        }
        let startParameter = try parameterization.parameterEnclosure(
            atArcLengthFraction: 0.0
        ).parameter
        return PreparedEvaluatedCurvePath(
            origin: try exactCurve.point(
                at: startParameter,
                tolerance: tolerance
            ),
            totalLength: totalLength,
            storage: .exact(
                curve: exactCurve,
                parameterization: parameterization
            )
        )
    }

    /// Prepares a reusable piecewise-linear path when no exact curve exists.
    public func prepare(
        points: [Point3D]
    ) throws -> PreparedEvaluatedCurvePath {
        try tolerance.validate()
        guard points.count >= 2 else {
            throw SketchError.unsupportedEntity(
                "Curve path preparation requires at least two points."
            )
        }
        var cumulativeLengths = [0.0]
        cumulativeLengths.reserveCapacity(points.count)
        var totalLength = 0.0
        for index in points.indices {
            try points[index].validate()
            guard index > points.startIndex else { continue }
            let segmentLength = (points[index] - points[index - 1]).length
            guard segmentLength.isFinite,
                  segmentLength > tolerance.distance else {
                throw SketchError.unsupportedEntity(
                    "Curve path preparation requires non-degenerate spans."
                )
            }
            totalLength += segmentLength
            cumulativeLengths.append(totalLength)
        }
        guard totalLength.isFinite,
              totalLength > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(totalLength)
        }
        return PreparedEvaluatedCurvePath(
            origin: points[0],
            totalLength: totalLength,
            storage: .polyline(
                points: points,
                cumulativeLengths: cumulativeLengths
            )
        )
    }

    /// Prepares every segment once so repeated distance queries do not rebuild
    /// certified arc-length partitions.
    public func prepare(
        _ segments: [EvaluatedCurvePathSegment]
    ) throws -> PreparedEvaluatedCurveChain {
        try tolerance.validate()
        guard segments.isEmpty == false else {
            throw SketchError.unsupportedEntity(
                "Curve path preparation requires at least one segment."
            )
        }
        var prepared: [PreparedEvaluatedCurveChain.Segment] = []
        prepared.reserveCapacity(segments.count)
        var totalLength = 0.0
        for segment in segments {
            try segment.validate(tolerance: tolerance)
            let path = try prepare(segment.curve)
            let startDistance = totalLength
            totalLength += path.totalLength
            guard totalLength.isFinite else {
                throw FeatureEvaluationError.invalidDistance(totalLength)
            }
            prepared.append(PreparedEvaluatedCurveChain.Segment(
                path: path,
                isReversed: segment.isReversed,
                startDistance: startDistance,
                endDistance: totalLength
            ))
        }
        guard totalLength > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(totalLength)
        }
        return PreparedEvaluatedCurveChain(
            totalLength: totalLength,
            segments: prepared
        )
    }

    /// Evaluates one point and tangent at a physical distance along a prepared path.
    public func sample(
        at distance: Double,
        on path: PreparedEvaluatedCurvePath
    ) throws -> EvaluatedCurvePathSample {
        try tolerance.validate()
        guard distance.isFinite,
              distance >= -tolerance.distance,
              distance <= path.totalLength + tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(distance)
        }
        let clampedDistance = min(max(distance, 0.0), path.totalLength)
        switch path.storage {
        case let .exact(curve, parameterization):
            let fraction = clampedDistance / path.totalLength
            let parameter = try parameterization.parameterEnclosure(
                atArcLengthFraction: fraction
            ).parameter
            let geometry = try curve.differentialGeometry(
                at: parameter,
                tolerance: tolerance
            )
            return EvaluatedCurvePathSample(
                point: geometry.position,
                tangent: geometry.tangent,
                distance: clampedDistance
            )
        case let .polyline(points, cumulativeLengths):
            let spanIndex = polylineSpanIndex(
                containing: clampedDistance,
                cumulativeLengths: cumulativeLengths
            )
            let startDistance = cumulativeLengths[spanIndex - 1]
            let endDistance = cumulativeLengths[spanIndex]
            let spanLength = endDistance - startDistance
            let start = points[spanIndex - 1]
            let end = points[spanIndex]
            let tangent = try (end - start).normalized(
                tolerance: tolerance.distance
            )
            let localFraction = (clampedDistance - startDistance) / spanLength
            return EvaluatedCurvePathSample(
                point: start + (end - start) * localFraction,
                tangent: tangent,
                distance: clampedDistance
            )
        }
    }

    /// Evaluates one point and tangent at a physical distance along a prepared chain.
    public func sample(
        at distance: Double,
        on chain: PreparedEvaluatedCurveChain
    ) throws -> EvaluatedCurvePathSample {
        try tolerance.validate()
        guard distance.isFinite,
              distance >= -tolerance.distance,
              distance <= chain.totalLength + tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(distance)
        }
        let clampedDistance = min(max(distance, 0.0), chain.totalLength)
        guard let segment = chain.segments.first(where: {
            clampedDistance <= $0.endDistance
        }) ?? chain.segments.last else {
            throw SketchError.unsupportedEntity(
                "Prepared curve chain contains no segments."
            )
        }
        let localDistance = min(
            max(clampedDistance - segment.startDistance, 0.0),
            segment.path.totalLength
        )
        let canonicalDistance = segment.isReversed
            ? segment.path.totalLength - localDistance
            : localDistance
        let canonicalSample = try sample(
            at: canonicalDistance,
            on: segment.path
        )
        return EvaluatedCurvePathSample(
            point: canonicalSample.point,
            tangent: segment.isReversed
                ? -canonicalSample.tangent
                : canonicalSample.tangent,
            distance: clampedDistance
        )
    }

    public func length(of curves: [EvaluatedCurve]) throws -> Double {
        try length(of: curves.map { EvaluatedCurvePathSegment(curve: $0) })
    }

    public func length(of segments: [EvaluatedCurvePathSegment]) throws -> Double {
        try prepare(segments).totalLength
    }

    public func length(of curve: EvaluatedCurve) throws -> Double {
        try prepare(curve).totalLength
    }

    public func samples(
        for curve: EvaluatedCurve,
        distanceFraction: Double = 1.0
    ) throws -> [EvaluatedCurvePathSample] {
        try tolerance.validate()
        try validateDistanceFraction(distanceFraction)
        return try samples(
            for: preparedSegment(
                EvaluatedCurvePathSegment(curve: curve)
            ),
            distanceFraction: distanceFraction
        )
    }

    public func samples(
        for segments: [EvaluatedCurvePathSegment],
        distanceFraction: Double = 1.0
    ) throws -> [EvaluatedCurvePathSample] {
        try tolerance.validate()
        try validateDistanceFraction(distanceFraction)
        guard segments.isEmpty == false else {
            throw SketchError.unsupportedEntity("Curve path sampling requires at least one segment.")
        }

        let preparedSegments = try segments.map(preparedSegment)
        let totalLength = preparedSegments.reduce(0.0) {
            $0 + $1.length
        }
        guard totalLength > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(totalLength)
        }

        let targetDistance = totalLength * distanceFraction
        var coveredDistance = 0.0
        var pathSamples: [EvaluatedCurvePathSample] = []
        for prepared in preparedSegments {
            let segmentLength = prepared.length
            let remainingDistance = targetDistance - coveredDistance
            guard remainingDistance > tolerance.distance else {
                break
            }
            let segmentTargetDistance = min(remainingDistance, segmentLength)
            let segmentFraction = segmentTargetDistance / segmentLength
            let segmentSamples = try samples(
                for: prepared,
                distanceFraction: segmentFraction
            )
            append(
                segmentSamples,
                distanceOffset: coveredDistance,
                to: &pathSamples
            )
            coveredDistance += segmentTargetDistance
            if targetDistance - coveredDistance <= tolerance.distance {
                break
            }
        }

        return try validateSamples(pathSamples)
    }

    private func validateDistanceFraction(_ distanceFraction: Double) throws {
        guard distanceFraction.isFinite,
              distanceFraction > 0.0,
              distanceFraction <= 1.0 else {
            throw FeatureEvaluationError.invalidDistance(distanceFraction)
        }
    }

    private func samples(
        for prepared: PreparedPathSegment,
        distanceFraction: Double
    ) throws -> [EvaluatedCurvePathSample] {
        let segment = prepared.segment
        let curve = segment.curve
        guard curve.exactCurve != nil else {
            return try polylineSamples(
                points: segment.isReversed
                    ? Array(curve.points.reversed())
                    : curve.points,
                distanceFraction: distanceFraction
            )
        }
        return try exactSamples(
            for: prepared,
            distanceFraction: distanceFraction
        )
    }

    private func preparedSegment(
        _ segment: EvaluatedCurvePathSegment
    ) throws -> PreparedPathSegment {
        try segment.validate(tolerance: tolerance)
        return PreparedPathSegment(
            segment: segment,
            path: try prepare(segment.curve)
        )
    }

    private func exactSamples(
        for prepared: PreparedPathSegment,
        distanceFraction: Double
    ) throws -> [EvaluatedCurvePathSample] {
        let path = prepared.path
        let targetLength = path.totalLength * distanceFraction
        guard targetLength.isFinite,
              targetLength > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(targetLength)
        }
        let segmentCount = try exactSampleSegmentCount(
            for: prepared.segment.curve,
            distanceFraction: distanceFraction
        )
        var samples: [EvaluatedCurvePathSample] = []
        samples.reserveCapacity(segmentCount + 1)
        for index in 0...segmentCount {
            let ratio = Double(index) / Double(segmentCount)
            let localDistance = targetLength * ratio
            let canonicalDistance = prepared.segment.isReversed
                ? path.totalLength - localDistance
                : localDistance
            let canonicalSample = try sample(
                at: canonicalDistance,
                on: path
            )
            samples.append(EvaluatedCurvePathSample(
                point: canonicalSample.point,
                tangent: prepared.segment.isReversed
                    ? -canonicalSample.tangent
                    : canonicalSample.tangent,
                distance: localDistance
            ))
        }
        return try validateSamples(samples)
    }

    private func exactSampleSegmentCount(
        for curve: EvaluatedCurve,
        distanceFraction: Double
    ) throws -> Int {
        guard let exactCurve = curve.exactCurve else {
            throw KernelError.unsupportedEvaluation(
                tolerance: tolerance,
                message: "Exact path sampling requires canonical curve geometry."
            )
        }
        let interval = try traversalInterval(
            for: curve,
            exactCurve: exactCurve
        )
        let parameterSpan = interval.width * distanceFraction
        return exactSampleSegmentCount(
            for: exactCurve,
            evaluatedCurve: curve,
            parameterSpan: parameterSpan
        )
    }

    private func exactSampleSegmentCount(
        for exactCurve: Curve3D,
        evaluatedCurve curve: EvaluatedCurve,
        parameterSpan: Double
    ) -> Int {
        switch exactCurve {
        case .line, .analytic(.line):
            return 1
        case let .circle(circle):
            return circularSegmentCount(
                radius: circle.radius,
                angleSpan: parameterSpan
            )
        case let .analytic(analyticCurve):
            let radiusScale: Double
            switch analyticCurve {
            case .line:
                return 1
            case let .circle(_, _, radius), let .arc(_, _, radius, _, _):
                radiusScale = radius
            case let .ellipse(_, _, _, majorRadius, _):
                radiusScale = majorRadius
            case let .hyperbola(hyperbola):
                radiusScale = max(
                    hyperbola.transverseRadius,
                    hyperbola.conjugateRadius
                )
            case let .parabola(parabola):
                radiusScale = 2.0 * parabola.focalLength
            case .planeTorus:
                return max(
                    min(maximumSplineSegmentCount, curve.points.count * 8),
                    32
                )
            }
            return circularSegmentCount(
                radius: radiusScale,
                angleSpan: parameterSpan
            )
        case let .bSpline(spline):
            return min(
                max(
                    curve.points.count - 1,
                    spline.controlPointCount * 2,
                    8
                ),
                maximumSplineSegmentCount
            )
        case .implicit, .surfaceLift, .certifiedIntersection:
            return max(
                min(maximumSplineSegmentCount, curve.points.count - 1),
                8
            )
        case let .rigidImage(image):
            return exactSampleSegmentCount(
                for: image.source,
                evaluatedCurve: curve,
                parameterSpan: parameterSpan
            )
        case let .affineImage(image):
            let sourceCount = exactSampleSegmentCount(
                for: image.source,
                evaluatedCurve: curve,
                parameterSpan: parameterSpan
            )
            let stretchSubdivision = max(
                1,
                Int(ceil(sqrt(max(
                    1.0,
                    image.transform.linearMagnitudeUpperBound
                ))))
            )
            return min(
                maximumSplineSegmentCount,
                sourceCount * stretchSubdivision
            )
        }
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

    private func traversalInterval(
        for curve: EvaluatedCurve,
        exactCurve: Curve3D
    ) throws -> ScalarInterval {
        switch curve.parameterDomain {
        case let .closed(lower, upper):
            return try ScalarInterval(lower: lower, upper: upper)
        case let .periodic(period):
            guard curve.isClosed,
                  let firstPoint = curve.points.first else {
                throw KernelError.unsupportedEvaluation(
                    tolerance: tolerance,
                    message: "Certified periodic curve path preparation requires a closed evaluated curve."
                )
            }
            let startParameter: Double
            if let exactStart = curve.exactPointParameters?.first {
                startParameter = exactStart
            } else {
                startParameter = try exactCurve.parameterProjection(
                    of: firstPoint,
                    tolerance: tolerance
                ).parameter
            }
            return try ScalarInterval(
                lower: startParameter,
                upper: startParameter + period
            )
        case .unbounded:
            throw KernelError.unsupportedEvaluation(
                tolerance: tolerance,
                message: "Certified curve path preparation requires an explicit bounded parameter interval."
            )
        }
    }

    private func polylineSpanIndex(
        containing distance: Double,
        cumulativeLengths: [Double]
    ) -> Int {
        if distance <= 0.0 {
            return 1
        }
        for index in 1..<cumulativeLengths.count
            where distance <= cumulativeLengths[index] {
            return index
        }
        return cumulativeLengths.count - 1
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

    private func append(
        _ segmentSamples: [EvaluatedCurvePathSample],
        distanceOffset: Double,
        to pathSamples: inout [EvaluatedCurvePathSample]
    ) {
        for sample in segmentSamples {
            if let last = pathSamples.last,
               last.point.isApproximatelyEqual(to: sample.point, tolerance: tolerance.distance) {
                continue
            }
            pathSamples.append(EvaluatedCurvePathSample(
                point: sample.point,
                tangent: sample.tangent,
                distance: distanceOffset + sample.distance
            ))
        }
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
