import CADCore

/// Exact constant-field classification from the original plane chart authority.
struct SurfaceSilhouettePlanarZeroAuthority {
    static func classification(surface: Surface3D, view: Vector3D,
                               tolerance: ModelingTolerance,
                               usage: inout SurfaceSilhouetteUsage) throws -> RobustSign? {
        typealias Vector = (x: ExactRationalCoefficient, y: ExactRationalCoefficient, z: ExactRationalCoefficient)
        func exact(_ value: Vector3D, usage: inout SurfaceSilhouetteUsage) throws -> Vector {
            let x = try ExactRationalCoefficient.originalDouble(value.x, usage: &usage)
            let y = try ExactRationalCoefficient.originalDouble(value.y, usage: &usage)
            let z = try ExactRationalCoefficient.originalDouble(value.z, usage: &usage)
            return (x, y, z)
        }
        func cross(_ a: Vector, _ b: Vector, usage: inout SurfaceSilhouetteUsage) throws -> Vector {
            let x = try a.y.multiplied(by: b.z, usage: &usage)
                .subtracting(a.z.multiplied(by: b.y, usage: &usage), usage: &usage)
            let y = try a.z.multiplied(by: b.x, usage: &usage)
                .subtracting(a.x.multiplied(by: b.z, usage: &usage), usage: &usage)
            let z = try a.x.multiplied(by: b.y, usage: &usage)
                .subtracting(a.y.multiplied(by: b.x, usage: &usage), usage: &usage)
            return (x, y, z)
        }
        let u: Vector, v: Vector
        switch surface {
        case let .plane(plane):
            if let originalU = plane.uDirection {
                try plane.validate(tolerance: tolerance)
                u = try exact(originalU, usage: &usage)
                let normal = try exact(plane.normal, usage: &usage)
                v = try cross(normal, u, usage: &usage)
            } else {
                let basis = try plane.parameterBasis(tolerance: tolerance)
                u = try exact(basis.u, usage: &usage)
                v = try exact(basis.v, usage: &usage)
            }
        case let .analytic(.plane(_, normal)):
            let basis = try OriginalStoredPlaneBasis.basis(normal,tolerance:tolerance)
            u = try exact(basis.u, usage: &usage)
            v = try exact(basis.v, usage: &usage)
        case .cylinder, .analytic, .bSpline, .procedural: return nil
        }
        let gauge = try cross(u, v, usage: &usage)
        let direction = try exact(view, usage: &usage)
        let first = try gauge.x.multiplied(by: direction.x, usage: &usage)
        let second = try gauge.y.multiplied(by: direction.y, usage: &usage)
        let third = try gauge.z.multiplied(by: direction.z, usage: &usage)
        let projection = try first.adding(second, usage: &usage).adding(third, usage: &usage)
        return projection.isZero ? .zero : projection.isPositive ? .positive : .negative
    }
}
