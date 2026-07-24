import CADCore

/// A directly evaluable certified intersection curve whose source surface
/// parameterizations are not regular across its complete parameter domain.
public enum CertifiedIntersectionCurve3D: Codable, Hashable, Sendable {
    case sphereCone(CertifiedSphereConeIntersectionCurve)
    case coneCone(CertifiedConeConeIntersectionCurve)
    case coneCylinder(CertifiedConeCylinderIntersectionCurve)
    case coneTorus(CertifiedGeneralConeTorusIntersectionCurve)
    case parallelTorusTorus(CertifiedParallelTorusTorusIntersectionCurve)

    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    public func validate(tolerance: ModelingTolerance) throws {
        switch self {
        case let .sphereCone(curve):
            try curve.validate(tolerance: tolerance)
        case let .coneCone(curve):
            try curve.validate(tolerance: tolerance)
        case let .coneCylinder(curve):
            try curve.validate(tolerance: tolerance)
        case let .coneTorus(curve):
            try curve.validate(tolerance: tolerance)
        case let .parallelTorusTorus(curve):
            try curve.validate(tolerance: tolerance)
        }
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        switch self {
        case let .sphereCone(curve):
            try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .coneCone(curve):
            try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .coneCylinder(curve):
            try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .coneTorus(curve):
            try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .parallelTorusTorus(curve):
            try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        }
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        switch self {
        case let .sphereCone(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .coneCone(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .coneCylinder(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .coneTorus(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .parallelTorusTorus(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        }
    }
}
