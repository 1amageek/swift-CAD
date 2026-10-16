import CADCore

/// Whole-chart equality of a materialized plane and its original signed offset.
enum OriginalPlaneOffsetRelation {
    private typealias Coefficient = ExactRationalCoefficient
    private typealias Vector = (x: Coefficient, y: Coefficient, z: Coefficient)

    static func proves<A: ExactScalarAdmission & ~Copyable>(source: Plane3D,
        target: Plane3D, distance: Double, tolerance: ModelingTolerance,
        using admission: inout A) throws -> Bool {
        try admission.checkpoint()
        try admission.admitDepth(value: 0, coefficient: 0)
        // Visit the original origins, normals, optional U vectors, and signed distance.
        try admission.consumeWork(13 + (source.uDirection == nil ? 0 : 6))
        try source.validate(tolerance: tolerance)
        guard distance.isFinite else { throw GeometryError.invalidDistance(distance) }
        guard target.origin.isFinite, target.normal == source.normal,
              target.uDirection == source.uDirection else { return false }

        let delta: Vector = (
            try Coefficient.originalDouble(target.origin.x, usage: &admission)
                .subtracting(Coefficient.originalDouble(source.origin.x, usage: &admission), usage: &admission),
            try Coefficient.originalDouble(target.origin.y, usage: &admission)
                .subtracting(Coefficient.originalDouble(source.origin.y, usage: &admission), usage: &admission),
            try Coefficient.originalDouble(target.origin.z, usage: &admission)
                .subtracting(Coefficient.originalDouble(source.origin.z, usage: &admission), usage: &admission))
        if distance == 0 {
            let equal = delta.x.isZero && delta.y.isZero && delta.z.isZero
            try admission.checkpoint()
            return equal
        }
        let normal = try vector(source.normal, using: &admission)
        let direction: Vector
        if let authored = source.uDirection {
            let u = try vector(authored, using: &admission)
            let v = try cross(normal, u, using: &admission)
            direction = try cross(u, v, using: &admission)
        } else {
            // The source-owned normalized-N basis has oriented cross direction N.
            direction = normal
        }
        guard try dot(direction, direction, using: &admission).isPositive else { return false }
        let perpendicular = try cross(delta, direction, using: &admission)
        guard perpendicular.x.isZero, perpendicular.y.isZero, perpendicular.z.isZero else { return false }
        let amount = try Coefficient.originalDouble(distance, usage: &admission)
        let squaredDistance = try amount.multiplied(by: amount, usage: &admission)
        let squaredDelta = try dot(delta, delta, using: &admission)
        guard try squaredDelta.subtracting(squaredDistance, usage: &admission).isZero else { return false }
        let directed = try dot(direction, delta, using: &admission)
        let equal = directed.canonicalSign == amount.canonicalSign
        try admission.checkpoint()
        return equal
    }

    private static func vector<A: ExactScalarAdmission & ~Copyable>(_ value: Vector3D,
        using admission: inout A) throws -> Vector {
        (try Coefficient.originalDouble(value.x, usage: &admission),
         try Coefficient.originalDouble(value.y, usage: &admission),
         try Coefficient.originalDouble(value.z, usage: &admission))
    }

    private static func cross<A: ExactScalarAdmission & ~Copyable>(_ first: Vector, _ second: Vector,
        using admission: inout A) throws -> Vector {
        (try first.y.multiplied(by: second.z, usage: &admission)
            .subtracting(first.z.multiplied(by: second.y, usage: &admission), usage: &admission),
         try first.z.multiplied(by: second.x, usage: &admission)
            .subtracting(first.x.multiplied(by: second.z, usage: &admission), usage: &admission),
         try first.x.multiplied(by: second.y, usage: &admission)
            .subtracting(first.y.multiplied(by: second.x, usage: &admission), usage: &admission))
    }

    private static func dot<A: ExactScalarAdmission & ~Copyable>(_ first: Vector, _ second: Vector,
        using admission: inout A) throws -> Coefficient {
        try first.x.multiplied(by: second.x, usage: &admission)
            .adding(first.y.multiplied(by: second.y, usage: &admission), usage: &admission)
            .adding(first.z.multiplied(by: second.z, usage: &admission), usage: &admission)
    }
}
