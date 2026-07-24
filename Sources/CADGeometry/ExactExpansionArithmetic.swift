import CADCore

enum ExactExpansionArithmetic {
    typealias Scalar = [Double]

    struct Vector3 {
        let x: Scalar
        let y: Scalar
        let z: Scalar
    }

    static func difference(_ lhs: Point3D, _ rhs: Point3D) -> Vector3 {
        Vector3(
            x: FloatingPointExpansion.difference(lhs.x, rhs.x),
            y: FloatingPointExpansion.difference(lhs.y, rhs.y),
            z: FloatingPointExpansion.difference(lhs.z, rhs.z)
        )
    }

    static func offset(
        _ point: Point3D,
        from origin: Point3D,
        exactU: Vector3,
        uFraction: Double,
        exactV: Vector3,
        vFraction: Double
    ) -> Vector3 {
        subtract(
            subtract(
                difference(point, origin),
                scaled(exactU, by: uFraction)
            ),
            scaled(exactV, by: vFraction)
        )
    }

    static func isZero(_ value: Vector3) -> Bool {
        sign(value.x) == .zero
            && sign(value.y) == .zero
            && sign(value.z) == .zero
    }

    static func dot(_ lhs: Vector3, _ rhs: Vector3) -> Scalar {
        add(
            add(
                multiply(lhs.x, rhs.x),
                multiply(lhs.y, rhs.y)
            ),
            multiply(lhs.z, rhs.z)
        )
    }

    static func tripleProduct(
        _ first: Vector3,
        _ second: Vector3,
        _ third: Vector3
    ) -> Scalar {
        dot(first, Vector3(
            x: subtract(
                multiply(second.y, third.z),
                multiply(second.z, third.y)
            ),
            y: subtract(
                multiply(second.z, third.x),
                multiply(second.x, third.z)
            ),
            z: subtract(
                multiply(second.x, third.y),
                multiply(second.y, third.x)
            )
        ))
    }

    static func scaled(_ value: Vector3, by scale: Double) -> Vector3 {
        Vector3(
            x: multiply(value.x, [scale]),
            y: multiply(value.y, [scale]),
            z: multiply(value.z, [scale])
        )
    }

    static func subtract(_ lhs: Vector3, _ rhs: Vector3) -> Vector3 {
        Vector3(
            x: subtract(lhs.x, rhs.x),
            y: subtract(lhs.y, rhs.y),
            z: subtract(lhs.z, rhs.z)
        )
    }

    static func sign(_ value: Scalar) -> RobustSign {
        FloatingPointExpansion.sign(value)
    }

    static func add(_ lhs: Scalar, _ rhs: Scalar) -> Scalar {
        FloatingPointExpansion.sum(lhs, rhs)
    }

    static func subtract(_ lhs: Scalar, _ rhs: Scalar) -> Scalar {
        FloatingPointExpansion.subtract(lhs, rhs)
    }

    static func multiply(_ lhs: Scalar, _ rhs: Scalar) -> Scalar {
        FloatingPointExpansion.product(lhs, rhs)
    }

    static func estimate(_ value: Scalar) -> Double {
        value.reduce(0.0, +)
    }
}
