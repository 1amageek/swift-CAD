import Foundation
import CADCore

struct CircularCurveSamplingPolicy: Sendable {
    static let standard = CircularCurveSamplingPolicy()

    let minimumSegmentCount: Int
    let maximumSegmentCount: Int

    init(minimumSegmentCount: Int = 32, maximumSegmentCount: Int = 8_192) {
        self.minimumSegmentCount = minimumSegmentCount
        self.maximumSegmentCount = Swift.max(maximumSegmentCount, minimumSegmentCount)
    }

    func boundedFullCircleSegmentCount(radius: Double, tolerance: ModelingTolerance) throws -> Int {
        try tolerance.validate()
        let requiredSegmentCount = try requiredSegmentCount(
            radius: radius,
            angleSpan: Double.pi * 2.0,
            tolerance: tolerance,
            minimumSegmentCount: minimumSegmentCount
        )
        let segmentCount = min(max(requiredSegmentCount, minimumSegmentCount), maximumSegmentCount)
        let edgeLength = 2.0 * radius * sin(Double.pi / Double(segmentCount))
        guard edgeLength > tolerance.distance else {
            throw SketchError.degenerateProfile
        }
        return segmentCount
    }

    func boundedArcSegmentCount(radius: Double, angleSpan: Double, tolerance: ModelingTolerance) throws -> Int {
        try tolerance.validate()
        let segmentCount = try requiredSegmentCount(
            radius: radius,
            angleSpan: angleSpan,
            tolerance: tolerance,
            minimumSegmentCount: 2
        )
        return min(max(segmentCount, 2), maximumSegmentCount)
    }

    /// The segment count that samples an arc of `radius` and `angleSpan` within both tessellation
    /// bounds: each segment turns by at most `angularTolerance` and deviates from the arc by at
    /// most `linearTolerance`. A step of angle φ deviates by `radius · (1 − cos(φ/2))`, which grows
    /// with the radius, so the turning bound alone cannot deliver the chord bound.
    ///
    /// The count never exceeds the modeling resolution: segments stay longer than the modeling
    /// distance, where the chord deviation is already far inside it.
    func boundedTessellationArcSegmentCount(
        radius: Double,
        angleSpan: Double,
        angularTolerance: Double,
        linearTolerance: Double,
        modelingTolerance: ModelingTolerance,
        maximumSegmentCount: Int = 65_536
    ) throws -> Int {
        try modelingTolerance.validate()
        guard radius.isFinite,
              radius > modelingTolerance.distance else {
            throw GeometryError.invalidRadius(radius)
        }
        guard angleSpan.isFinite,
              angleSpan > modelingTolerance.angle else {
            throw GeometryError.invalidAngle(angleSpan)
        }
        guard angularTolerance.isFinite, angularTolerance > 0.0,
              linearTolerance.isFinite, linearTolerance > 0.0 else {
            throw GeometryError.invalidTolerance(distance: linearTolerance, angle: angularTolerance)
        }

        let chordAngle = maxSegmentAngle(radius: radius, deviation: linearTolerance)
        let requested = max(ceil(angleSpan / angularTolerance), ceil(angleSpan / chordAngle))
        guard requested.isFinite,
              requested <= Double(Int.max) else {
            throw SketchError.unsupportedProfile(
                "Circular tessellation exceeds the supported segment count."
            )
        }
        let stableMaximum = try maximumNondegenerateSegmentCount(
            radius: radius,
            angleSpan: angleSpan,
            tolerance: modelingTolerance,
            maximumSegmentCount: maximumSegmentCount
        )
        return min(max(Int(requested), 2), stableMaximum, maximumSegmentCount)
    }

    private func requiredSegmentCount(
        radius: Double,
        angleSpan: Double,
        tolerance: ModelingTolerance,
        minimumSegmentCount: Int
    ) throws -> Int {
        guard radius.isFinite, radius > tolerance.distance else {
            throw GeometryError.invalidRadius(radius)
        }
        guard angleSpan.isFinite, angleSpan > tolerance.angle else {
            throw SketchError.degenerateProfile
        }

        let maxAngle = maxSegmentAngle(radius: radius, deviation: tolerance.distance)
        let required = ceil(angleSpan / maxAngle)
        guard required.isFinite, required <= Double(Int.max) else {
            throw SketchError.unsupportedProfile(
                "Circular profile tessellation exceeds the supported segment count."
            )
        }
        return max(Int(required), minimumSegmentCount)
    }

    /// The largest step angle whose chord deviates from a circle of `radius` by at most
    /// `deviation`.
    private func maxSegmentAngle(radius: Double, deviation: Double) -> Double {
        let ratio = deviation / radius
        if ratio < 1.0e-4 {
            return 2.0 * sqrt(2.0 * ratio)
        }
        return 2.0 * acos(1.0 - min(ratio, 1.0))
    }

    private func maximumNondegenerateSegmentCount(
        radius: Double,
        angleSpan: Double,
        tolerance: ModelingTolerance,
        maximumSegmentCount: Int
    ) throws -> Int {
        let minimumSegmentAngle = 2.0 * asin(min(tolerance.distance / (2.0 * radius), 1.0))
        guard minimumSegmentAngle.isFinite,
              minimumSegmentAngle > 0.0 else {
            throw SketchError.degenerateProfile
        }
        let rawMaximum = floor(angleSpan / minimumSegmentAngle)
        guard rawMaximum.isFinite,
              rawMaximum >= 2.0 else {
            throw SketchError.degenerateProfile
        }

        var segmentCount = min(Int(rawMaximum), maximumSegmentCount)
        while segmentCount >= 2 {
            let segmentAngle = angleSpan / Double(segmentCount)
            let chordLength = 2.0 * radius * sin(segmentAngle / 2.0)
            if chordLength > tolerance.distance {
                return segmentCount
            }
            segmentCount -= 1
        }
        throw SketchError.degenerateProfile
    }
}
