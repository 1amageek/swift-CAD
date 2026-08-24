import Foundation
import CADCore
import CADGeometry
import CADModeling

/// Groups curves by certified geometric support when subdivision junctions
/// must be shared across independently authored topology.
struct CurveSupportIdentityRegistry: Sendable {
    private enum Record: Sendable {
        case exactLinear(origin: Point3D, direction: Vector3D)
        case exactCurve(Curve3D)
    }

    private var records: [Record] = []

    mutating func identity(
        for edge: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) -> ExactCurveIdentity {
        if let line = exactLinearSupport(of: edge, tolerance: tolerance) {
            if let index = records.firstIndex(where: {
                matches(line, record: $0, tolerance: tolerance)
            }) {
                return ExactCurveIdentity(ordinal: index)
            }
            records.append(.exactLinear(
                origin: line.origin,
                direction: line.direction
            ))
            return ExactCurveIdentity(ordinal: records.count - 1)
        }
        if let index = records.firstIndex(where: { record in
            guard case let .exactCurve(curve) = record else { return false }
            return curve == edge.curve
        }) {
            return ExactCurveIdentity(ordinal: index)
        }
        records.append(.exactCurve(edge.curve))
        return ExactCurveIdentity(ordinal: records.count - 1)
    }

    private func exactLinearSupport(
        of edge: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) -> (origin: Point3D, direction: Vector3D)? {
        guard edge.curve.hasExactLinearParameterization else { return nil }
        let delta = edge.endPoint - edge.startPoint
        let length = delta.length
        guard length > tolerance.distance else { return nil }
        return (edge.startPoint, delta / length)
    }

    private func matches(
        _ candidate: (origin: Point3D, direction: Vector3D),
        record: Record,
        tolerance: ModelingTolerance
    ) -> Bool {
        guard case let .exactLinear(origin, direction) = record else {
            return false
        }
        let angularResidual = candidate.direction.cross(direction).length
        guard angularResidual <= max(
            sin(tolerance.angle),
            tolerance.relative
        ) else {
            return false
        }
        return (candidate.origin - origin).cross(direction).length
            <= tolerance.distance
    }
}
