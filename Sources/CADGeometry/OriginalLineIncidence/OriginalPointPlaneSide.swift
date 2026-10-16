import CADCore

/// Exact side from original point, origin and normal coefficients.
package struct OriginalPointPlaneSide: Sendable {
    package init() {}

    package func sign<A: ExactScalarAdmission & ~Copyable>(point: Point3D, origin: Point3D,
        normal: Vector3D, using execution: inout A) throws -> RobustSign {
        try execution.consumeWork(1)
        try point.validate(); try origin.validate(); try normal.validate()
        guard normal.x != 0 || normal.y != 0 || normal.z != 0 else {
            throw GeometryConversionError.invalidInput("Exact plane side requires a nonzero original normal.")
        }
        var result: [Double] = []
        for axis in 0..<3 {
            try execution.consumeWork(1)
            let values: (Double, Double, Double)
            switch axis {
            case 0: values = (point.x, origin.x, normal.x)
            case 1: values = (point.y, origin.y, normal.y)
            default: values = (point.z, origin.z, normal.z)
            }
            let offset = try FloatingPointExpansion.difference(values.0, values.1, using: &execution)
            try OriginalCoefficientAllocation.reserve(count: 1, of: Double.self, using: &execution)
            let component = try FloatingPointExpansion.product(offset, [values.2], using: &execution)
            result = try FloatingPointExpansion.sum(result, component, using: &execution)
        }
        let side = try FloatingPointExpansion.sign(result, using: &execution)
        guard side != .indeterminate else {
            throw GeometryConversionError.resourceLimitExceeded("Exact original plane side expansion is indeterminate.")
        }
        try execution.checkpoint()
        return side
    }
}
