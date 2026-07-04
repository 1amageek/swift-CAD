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

    func fullCircleSegmentCount(radius: Double, tolerance: ModelingTolerance) throws -> Int {
        let ratio = min(max(tolerance.distance / radius, 1.0e-9), 0.5)
        let angle = 2.0 * acos(1.0 - ratio)
        let requiredSegmentCount = Int(ceil((Double.pi * 2.0) / angle))
        let segmentCount = min(
            max(requiredSegmentCount, minimumSegmentCount),
            maximumSegmentCount
        )
        let edgeLength = 2.0 * radius * sin(Double.pi / Double(segmentCount))
        guard edgeLength > tolerance.distance else {
            throw SketchError.degenerateProfile
        }
        return segmentCount
    }

    func arcSegmentCount(radius: Double, angleSpan: Double, tolerance: ModelingTolerance) throws -> Int {
        let fullCircleSegmentCount = try fullCircleSegmentCount(
            radius: radius,
            tolerance: tolerance
        )
        let proportionalCount = Int(ceil(Double(fullCircleSegmentCount) * angleSpan / (Double.pi * 2.0)))
        return max(proportionalCount, 2)
    }
}
