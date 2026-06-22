import CADCore
import Foundation

struct SweepSectionTransform: Sendable, Hashable {
    var twistAngle: Double
    var endScale: Double

    init(twistAngle: Double = 0.0, endScale: Double = 1.0) {
        self.twistAngle = twistAngle
        self.endScale = endScale
    }

    func transformed(
        _ point: Point2D,
        at frame: SweepPathFrame,
        startDistance: Double,
        totalDistance: Double,
        tolerance: ModelingTolerance
    ) throws -> Point2D {
        guard totalDistance.isFinite,
              totalDistance > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(totalDistance)
        }
        let rawRatio = (frame.distance - startDistance) / totalDistance
        let ratio = min(max(rawRatio, 0.0), 1.0)
        let scale = 1.0 + (endScale - 1.0) * ratio
        guard scale.isFinite,
              scale > tolerance.distance else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep section scale collapses the profile before producing valid topology."
            )
        }

        let scaledX = point.x * scale
        let scaledY = point.y * scale
        let angle = twistAngle * ratio
        guard abs(angle) > tolerance.angle else {
            return Point2D(x: scaledX, y: scaledY)
        }

        let cosine = cos(angle)
        let sine = sin(angle)
        return Point2D(
            x: scaledX * cosine - scaledY * sine,
            y: scaledX * sine + scaledY * cosine
        )
    }

    func isIdentity(tolerance: ModelingTolerance) -> Bool {
        abs(twistAngle) <= tolerance.angle
            && abs(endScale - 1.0) <= tolerance.distance
    }
}
