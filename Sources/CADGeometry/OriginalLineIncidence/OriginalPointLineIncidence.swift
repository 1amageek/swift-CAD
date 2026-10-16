import CADCore

/// Exact incidence without constructing or normalizing an axis point.
package struct OriginalPointLineIncidence: Sendable {
    package init() {}

    package func contains<A: ExactScalarAdmission & ~Copyable>(point: Point3D, origin: Point3D,
        direction: Vector3D, using execution: inout A) throws -> Bool {
        try execution.consumeWork(1)
        try point.validate(); try origin.validate(); try direction.validate()
        guard direction.x != 0 || direction.y != 0 || direction.z != 0 else {
            throw GeometryConversionError.invalidInput("Exact line incidence requires an original nonzero direction.")
        }
        let x = try FloatingPointExpansion.difference(point.x, origin.x, using: &execution)
        let y = try FloatingPointExpansion.difference(point.y, origin.y, using: &execution)
        let z = try FloatingPointExpansion.difference(point.z, origin.z, using: &execution)
        for axis in 0..<3 {
            try execution.consumeWork(1)
            let first: [Double], second: [Double], a: Double, b: Double
            switch axis {
            case 0: (first, second, a, b) = (y, z, direction.z, direction.y)
            case 1: (first, second, a, b) = (z, x, direction.x, direction.z)
            default: (first, second, a, b) = (x, y, direction.y, direction.x)
            }
            try OriginalCoefficientAllocation.reserve(count: 2, of: Double.self, using: &execution)
            let left = try FloatingPointExpansion.product(first, [a], using: &execution)
            let right = try FloatingPointExpansion.product(second, [b], using: &execution)
            let component = try FloatingPointExpansion.subtract(left, right, using: &execution)
            switch try FloatingPointExpansion.sign(component, using: &execution) {
            case .zero: continue
            case .negative, .positive:
                try execution.checkpoint()
                return false
            case .indeterminate:
                throw GeometryConversionError.resourceLimitExceeded("Exact original line incidence expansion is indeterminate.")
            }
        }
        try execution.checkpoint()
        return true
    }
}
