import Foundation
import CADCore
import CADGeometry
import CADModeling
import CADTopology

/// Groups curves by certified geometric support when subdivision junctions
/// must be shared across independently authored topology.
struct CurveSupportIdentityRegistry: Sendable {
    private enum Record: Sendable {
        case exactLinear(origin: Point3D, direction: Vector3D)
        case exactCurve(Curve3D)
    }

    private var records: [Record] = []

    // FIXME(INCOMPLETE_IMPLEMENTATION): Production Boolean arrangement support
    // identity still uses angular/distance proximity for linear proposals.
    // Original support equality must replace this gate before exact identity.
    mutating func identity(
        for edge: BRepSewingEdge,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> ExactCurveIdentity {
        try execution.consumeWork(1)
        if let line = exactLinearSupport(of: edge, tolerance: tolerance) {
            for (index, record) in records.enumerated() {
                try execution.consumeWork(1)
                if matches(line, record: record, tolerance: tolerance) { return ExactCurveIdentity(ordinal: index) }
            }
            try OriginalParameterQueryStorage.append(.exactLinear(
                origin: line.origin,
                direction: line.direction
            ), to: &records, using: &execution)
            return ExactCurveIdentity(ordinal: records.count - 1)
        }
        for (index, record) in records.enumerated() {
            try execution.consumeWork(1)
            guard case let .exactCurve(curve) = record else { continue }
            if curve == edge.curve { return ExactCurveIdentity(ordinal: index) }
        }
        try OriginalParameterQueryStorage.append(.exactCurve(edge.curve), to: &records, using: &execution)
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
