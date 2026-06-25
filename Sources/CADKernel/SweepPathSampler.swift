import CADCore

public struct SweepPathSampler: SweepPathSampling {
    private let tolerance: ModelingTolerance
    private let pathEvaluator: EvaluatedCurvePathEvaluator

    public init(tolerance: ModelingTolerance = .standard) {
        self.tolerance = tolerance
        self.pathEvaluator = EvaluatedCurvePathEvaluator(tolerance: tolerance)
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

        let sampledPath = try pathEvaluator.samples(
            for: curve,
            distanceFraction: distanceFraction
        )
        var frames: [SweepPathFrame] = []
        frames.reserveCapacity(sampledPath.count)
        var previousNormal: Vector3D?

        for sample in sampledPath {
            let normal = try transportedNormal(
                tangent: sample.tangent,
                previousNormal: previousNormal,
                preferredNormal: preferredNormal
            )
            let binormal = try sample.tangent.cross(normal).normalized(tolerance: tolerance.distance)
            let correctedNormal = try binormal.cross(sample.tangent).normalized(tolerance: tolerance.distance)
            let frame = SweepPathFrame(
                origin: sample.point,
                tangent: sample.tangent,
                normal: correctedNormal,
                binormal: binormal,
                distance: sample.distance
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
