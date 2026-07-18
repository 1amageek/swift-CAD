import Foundation
import CADCore

struct MeridianCircleIntersector: Sendable {
    struct Point: Sendable {
        let radius: Double
        let axis: Double
    }

    struct Result: Sendable {
        let points: [Point]
        let isTangent: Bool
        let isCoincident: Bool
    }

    func intersections(
        firstCenter: Point,
        firstRadius: Double,
        secondCenter: Point,
        secondRadius: Double,
        tolerance: ModelingTolerance
    ) throws -> Result {
        try tolerance.validate()
        let deltaRadius = secondCenter.radius - firstCenter.radius
        let deltaAxis = secondCenter.axis - firstCenter.axis
        let centerDistance = hypot(deltaRadius, deltaAxis)
        if centerDistance <= tolerance.distance {
            return Result(
                points: [],
                isTangent: false,
                isCoincident: abs(firstRadius - secondRadius) <= tolerance.distance
            )
        }
        let radiusSum = firstRadius + secondRadius
        let radiusDifference = abs(firstRadius - secondRadius)
        if centerDistance > radiusSum + tolerance.distance
            || centerDistance < radiusDifference - tolerance.distance {
            return Result(points: [], isTangent: false, isCoincident: false)
        }
        let centerlineDistance = (
            firstRadius * firstRadius
                - secondRadius * secondRadius
                + centerDistance * centerDistance
        ) / (2.0 * centerDistance)
        let halfChordSquared = firstRadius * firstRadius
            - centerlineDistance * centerlineDistance
        guard halfChordSquared >= -tolerance.distance * tolerance.distance else {
            return Result(points: [], isTangent: false, isCoincident: false)
        }

        let directionRadius = deltaRadius / centerDistance
        let directionAxis = deltaAxis / centerDistance
        let baseRadius = firstCenter.radius
            + directionRadius * centerlineDistance
        let baseAxis = firstCenter.axis
            + directionAxis * centerlineDistance
        let halfChord = sqrt(max(0.0, halfChordSquared))
        if halfChord <= tolerance.distance {
            return Result(
                points: [Point(radius: baseRadius, axis: baseAxis)],
                isTangent: true,
                isCoincident: false
            )
        }
        let perpendicularRadius = -directionAxis
        let perpendicularAxis = directionRadius
        let points = [
            Point(
                radius: baseRadius + perpendicularRadius * halfChord,
                axis: baseAxis + perpendicularAxis * halfChord
            ),
            Point(
                radius: baseRadius - perpendicularRadius * halfChord,
                axis: baseAxis - perpendicularAxis * halfChord
            ),
        ].sorted(by: pointOrder)
        return Result(points: points, isTangent: false, isCoincident: false)
    }

    private func pointOrder(_ lhs: Point, _ rhs: Point) -> Bool {
        if lhs.axis != rhs.axis { return lhs.axis < rhs.axis }
        return lhs.radius < rhs.radius
    }
}
