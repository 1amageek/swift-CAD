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

    func boundedTessellationArcSegmentCount(
        radius: Double,
        angleSpan: Double,
        angularTolerance: Double,
        modelingTolerance: ModelingTolerance,
        maximumSegmentCount: Int = 65_536
    ) throws -> Int {
        try modelingTolerance.validate()
        guard radius.isFinite,
              radius > modelingTolerance.distance else {
            throw GeometryError.invalidRadius(radius)
        }
        guard angleSpan.isFinite,
              angleSpan > modelingTolerance.angle,
              angularTolerance.isFinite,
              angularTolerance > 0.0 else {
            throw GeometryError.invalidAngle(angleSpan)
        }

        let requested = ceil(angleSpan / angularTolerance)
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

        let maxAngle = maxSegmentAngle(radius: radius, tolerance: tolerance)
        let required = ceil(angleSpan / maxAngle)
        guard required.isFinite, required <= Double(Int.max) else {
            throw SketchError.unsupportedProfile(
                "Circular profile tessellation exceeds the supported segment count."
            )
        }
        return max(Int(required), minimumSegmentCount)
    }

    private func maxSegmentAngle(radius: Double, tolerance: ModelingTolerance) -> Double {
        let ratio = tolerance.distance / radius
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
