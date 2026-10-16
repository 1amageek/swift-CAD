import CADCore

/// Exact original harmonic coefficient identity for a complete regular cylinder.
struct SurfaceSilhouetteCylindricalZeroAuthority {
    static func isIdenticallyZero(surface: Surface3D, view: Vector3D,
        tolerance: ModelingTolerance, usage: inout OriginalQueryExecution) throws -> Bool {
        let axis: Vector3D, basis: (u: Vector3D, v: Vector3D)
        switch surface {
        case .cylinder(let source):
            axis = source.axis; basis = try circleOrthonormalBasis(source.axis, tolerance: tolerance)
        case .analytic(.cylinder(_, let sourceAxis, _)):
            axis = sourceAxis; basis = try analyticOrthonormalBasis(sourceAxis, tolerance: tolerance)
        default: return false
        }
        func exact(_ value: Vector3D, usage: inout OriginalQueryExecution) throws -> [ExactRationalCoefficient] {
            try RationalAlgebraStorage.retain(3, of: ExactRationalCoefficient.self, usage: &usage)
            return try [ExactRationalCoefficient.originalDouble(value.x, usage: &usage),
                .originalDouble(value.y, usage: &usage), .originalDouble(value.z, usage: &usage)]
        }
        func cross(_ a: [ExactRationalCoefficient], _ b: [ExactRationalCoefficient],
            usage: inout OriginalQueryExecution) throws -> [ExactRationalCoefficient] {
            try RationalAlgebraStorage.retain(3, of: ExactRationalCoefficient.self, usage: &usage)
            var result: [ExactRationalCoefficient] = []; result.reserveCapacity(3)
            for axis in 0..<3 {
                let j = (axis + 1) % 3, k = (axis + 2) % 3
                result.append(try a[j].multiplied(by: b[k], usage: &usage)
                    .subtracting(a[k].multiplied(by: b[j], usage: &usage), usage: &usage))
            }
            return result
        }
        func dot(_ a: [ExactRationalCoefficient], _ b: [ExactRationalCoefficient],
            usage: inout OriginalQueryExecution) throws -> ExactRationalCoefficient {
            var result = ExactRationalCoefficient.zero
            for axis in 0..<3 {
                result = try result.adding(a[axis].multiplied(by: b[axis], usage: &usage), usage: &usage)
            }
            return result
        }
        let u = try exact(basis.u, usage: &usage), v = try exact(basis.v, usage: &usage)
        let axial = try exact(axis, usage: &usage), direction = try exact(view, usage: &usage)
        guard try !dot(cross(u, v, usage: &usage), axial, usage: &usage).isZero else {
            throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                message: "Original cylinder harmonic normal coefficients do not establish whole direction regularity.")
        }
        let first = try cross(u, axial, usage: &usage), second = try cross(v, axial, usage: &usage)
        return try dot(first, direction, usage: &usage).isZero && dot(second, direction, usage: &usage).isZero
    }
}
