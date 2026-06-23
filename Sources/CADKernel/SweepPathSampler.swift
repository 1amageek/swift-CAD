import CADCore

public struct SweepPathSampler: SweepPathSampling {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance = .standard) {
        self.tolerance = tolerance
    }

    public func frames(
        for curve: EvaluatedCurve,
        distanceFraction: Double = 1.0,
        preferredNormal: Vector3D? = nil
    ) throws -> [SweepPathFrame] {
        try tolerance.validate()
        try curve.validate(tolerance: tolerance)
        guard distanceFraction.isFinite,
              distanceFraction > 0.0,
              distanceFraction <= 1.0 else {
            throw FeatureEvaluationError.invalidDistance(distanceFraction)
        }

        let sampledPath = try truncatedPath(
            points: curve.points,
            distanceFraction: distanceFraction
        )
        var frames: [SweepPathFrame] = []
        frames.reserveCapacity(sampledPath.points.count)
        var previousNormal: Vector3D?

        for index in sampledPath.points.indices {
            let tangent = try tangentVector(at: index, points: sampledPath.points)
            let normal = try transportedNormal(
                tangent: tangent,
                previousNormal: previousNormal,
                preferredNormal: preferredNormal
            )
            let binormal = try tangent.cross(normal).normalized(tolerance: tolerance.distance)
            let correctedNormal = try binormal.cross(tangent).normalized(tolerance: tolerance.distance)
            let frame = SweepPathFrame(
                origin: sampledPath.points[index],
                tangent: tangent,
                normal: correctedNormal,
                binormal: binormal,
                distance: sampledPath.distances[index]
            )
            try frame.validate(tolerance: tolerance)
            frames.append(frame)
            previousNormal = correctedNormal
        }

        guard frames.count >= 2 else {
            throw SketchError.unsupportedEntity("Sweep path sampling requires at least two frames.")
        }
        return frames
    }

    public func straightPath(from frames: [SweepPathFrame]) throws -> SweepStraightPath? {
        guard let first = frames.first,
              let last = frames.last else {
            return nil
        }
        for frame in frames {
            try frame.validate(tolerance: tolerance)
        }
        let chord = last.origin - first.origin
        guard chord.length > tolerance.distance else {
            return nil
        }
        let direction = try chord.normalized(tolerance: tolerance.distance)
        let pathLength = last.distance - first.distance
        guard abs(pathLength - chord.length) <= max(tolerance.distance, tolerance.angle * pathLength) else {
            return nil
        }
        for frame in frames {
            let offset = frame.origin - first.origin
            let perpendicular = offset - direction * offset.dot(direction)
            guard perpendicular.length <= tolerance.distance,
                  abs(abs(frame.tangent.dot(direction)) - 1.0) <= max(tolerance.distance, tolerance.angle) else {
                return nil
            }
        }
        return SweepStraightPath(
            start: first.origin,
            end: last.origin,
            direction: direction,
            distance: pathLength
        )
    }

    private func truncatedPath(
        points: [Point3D],
        distanceFraction: Double
    ) throws -> (points: [Point3D], distances: [Double]) {
        guard let first = points.first else {
            throw SketchError.unsupportedEntity("Sweep path has no points.")
        }
        var segmentLengths: [Double] = []
        segmentLengths.reserveCapacity(max(points.count - 1, 0))
        var totalLength = 0.0
        for index in 0..<(points.count - 1) {
            let length = (points[index + 1] - points[index]).length
            guard length > tolerance.distance else {
                throw SketchError.unsupportedEntity("Sweep path contains a degenerate span.")
            }
            segmentLengths.append(length)
            totalLength += length
        }
        guard totalLength > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(totalLength)
        }

        let targetDistance = totalLength * distanceFraction
        var sampledPoints = [first]
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
        return (sampledPoints, distances)
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

    private func tangentVector(at index: Int, points: [Point3D]) throws -> Vector3D {
        if index == points.startIndex {
            return try (points[index + 1] - points[index]).normalized(tolerance: tolerance.distance)
        }
        if index == points.index(before: points.endIndex) {
            return try (points[index] - points[index - 1]).normalized(tolerance: tolerance.distance)
        }
        return try (points[index + 1] - points[index - 1]).normalized(tolerance: tolerance.distance)
    }

    private func transportedNormal(
        tangent: Vector3D,
        previousNormal: Vector3D?,
        preferredNormal: Vector3D?
    ) throws -> Vector3D {
        if let previousNormal {
            let projected = previousNormal - tangent * previousNormal.dot(tangent)
            if projected.length > tolerance.distance {
                return try projected.normalized(tolerance: tolerance.distance)
            }
        }
        if let preferredNormal {
            let projected = preferredNormal - tangent * preferredNormal.dot(tangent)
            if projected.length > tolerance.distance {
                return try projected.normalized(tolerance: tolerance.distance)
            }
        }
        let helper = abs(tangent.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        return try helper.cross(tangent).normalized(tolerance: tolerance.distance)
    }
}
