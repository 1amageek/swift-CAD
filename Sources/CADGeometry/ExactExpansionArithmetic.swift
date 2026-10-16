import CADCore

enum ExactExpansionArithmetic {
    typealias Scalar = [Double]

    struct Vector3 {
        let x: Scalar
        let y: Scalar
        let z: Scalar
    }

    static func difference<A: ExactScalarAdmission & ~Copyable>(_ lhs: Point3D, _ rhs: Point3D, using execution: inout A) throws -> Vector3 {
        Vector3(
            x: try FloatingPointExpansion.difference(lhs.x, rhs.x, using: &execution),
            y: try FloatingPointExpansion.difference(lhs.y, rhs.y, using: &execution),
            z: try FloatingPointExpansion.difference(lhs.z, rhs.z, using: &execution)
        )
    }

    static func offset<A: ExactScalarAdmission & ~Copyable>(
        _ point: Point3D,
        from origin: Point3D,
        exactU: Vector3,
        uFraction: Double,
        exactV: Vector3,
        vFraction: Double,
    using execution: inout A) throws -> Vector3 {
        try subtract(
            try subtract(
                try difference(point, origin, using: &execution),
                try scaled(exactU, by: uFraction, using: &execution),
            using: &execution),
            try scaled(exactV, by: vFraction, using: &execution),
        using: &execution)
    }

    static func isZero<A: ExactScalarAdmission & ~Copyable>(_ value: Vector3, using execution: inout A) throws -> Bool {
        try sign(value.x, using: &execution) == .zero
            && sign(value.y, using: &execution) == .zero
            && sign(value.z, using: &execution) == .zero
    }

    static func dot<A: ExactScalarAdmission & ~Copyable>(_ lhs: Vector3, _ rhs: Vector3, using execution: inout A) throws -> Scalar {
        try add(
            try add(
                try multiply(lhs.x, rhs.x, using: &execution),
                try multiply(lhs.y, rhs.y, using: &execution),
            using: &execution),
            try multiply(lhs.z, rhs.z, using: &execution),
        using: &execution)
    }

    static func tripleProduct<A: ExactScalarAdmission & ~Copyable>(
        _ first: Vector3,
        _ second: Vector3,
        _ third: Vector3,
    using execution: inout A) throws -> Scalar {
        try dot(first, Vector3(
            x: try subtract(
                try multiply(second.y, third.z, using: &execution),
                try multiply(second.z, third.y, using: &execution),
            using: &execution),
            y: try subtract(
                try multiply(second.z, third.x, using: &execution),
                try multiply(second.x, third.z, using: &execution),
            using: &execution),
            z: try subtract(
                try multiply(second.x, third.y, using: &execution),
                try multiply(second.y, third.x, using: &execution),
            using: &execution)
        ), using: &execution)
    }

    static func scaled<A: ExactScalarAdmission & ~Copyable>(_ value: Vector3, by scale: Double, using execution: inout A) throws -> Vector3 {
        let scalar = try OriginalCoefficientAllocation.singleton(scale, using: &execution)
        return Vector3(
            x: try multiply(value.x, scalar, using: &execution),
            y: try multiply(value.y, scalar, using: &execution),
            z: try multiply(value.z, scalar, using: &execution)
        )
    }

    static func subtract<A: ExactScalarAdmission & ~Copyable>(_ lhs: Vector3, _ rhs: Vector3, using execution: inout A) throws -> Vector3 {
        Vector3(
            x: try subtract(lhs.x, rhs.x, using: &execution),
            y: try subtract(lhs.y, rhs.y, using: &execution),
            z: try subtract(lhs.z, rhs.z, using: &execution)
        )
    }

    static func sign<A: ExactScalarAdmission & ~Copyable>(_ value: Scalar, using execution: inout A) throws -> RobustSign {
        try FloatingPointExpansion.sign(value, using: &execution)
    }

    static func add<A: ExactScalarAdmission & ~Copyable>(_ lhs: Scalar, _ rhs: Scalar, using execution: inout A) throws -> Scalar {
        try FloatingPointExpansion.sum(lhs, rhs, using: &execution)
    }

    static func subtract<A: ExactScalarAdmission & ~Copyable>(_ lhs: Scalar, _ rhs: Scalar, using execution: inout A) throws -> Scalar {
        try FloatingPointExpansion.subtract(lhs, rhs, using: &execution)
    }

    static func multiply<A: ExactScalarAdmission & ~Copyable>(_ lhs: Scalar, _ rhs: Scalar, using execution: inout A) throws -> Scalar {
        try FloatingPointExpansion.product(lhs, rhs, using: &execution)
    }

    static func estimate<A: ExactScalarAdmission & ~Copyable>(_ value: Scalar, using execution: inout A) throws -> Double {
        try FloatingPointExpansion.estimate(value, using: &execution)
    }

    static func difference(_ lhs: Point3D, _ rhs: Point3D) throws -> Vector3 {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try difference(lhs, rhs, using: &execution)
    }

    static func offset(_ point: Point3D, from origin: Point3D, exactU: Vector3, uFraction: Double, exactV: Vector3, vFraction: Double) throws -> Vector3 {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try offset(point, from: origin, exactU: exactU, uFraction: uFraction, exactV: exactV, vFraction: vFraction, using: &execution)
    }

    static func isZero(_ value: Vector3) throws -> Bool {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try isZero(value, using: &execution)
    }

    static func dot(_ lhs: Vector3, _ rhs: Vector3) throws -> Scalar {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try dot(lhs, rhs, using: &execution)
    }

    static func tripleProduct(_ first: Vector3, _ second: Vector3, _ third: Vector3) throws -> Scalar {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try tripleProduct(first, second, third, using: &execution)
    }

    static func scaled(_ value: Vector3, by scale: Double) throws -> Vector3 {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try scaled(value, by: scale, using: &execution)
    }

    static func subtract(_ lhs: Vector3, _ rhs: Vector3) throws -> Vector3 {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try subtract(lhs, rhs, using: &execution)
    }

    static func sign(_ value: Scalar) throws -> RobustSign {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try sign(value, using: &execution)
    }

    static func add(_ lhs: Scalar, _ rhs: Scalar) throws -> Scalar {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try add(lhs, rhs, using: &execution)
    }

    static func subtract(_ lhs: Scalar, _ rhs: Scalar) throws -> Scalar {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try subtract(lhs, rhs, using: &execution)
    }

    static func multiply(_ lhs: Scalar, _ rhs: Scalar) throws -> Scalar {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try multiply(lhs, rhs, using: &execution)
    }

    static func estimate(_ value: Scalar) throws -> Double {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try estimate(value, using: &execution)
    }

}
