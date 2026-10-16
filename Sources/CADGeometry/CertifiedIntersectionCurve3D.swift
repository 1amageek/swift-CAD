import CADCore

/// A directly evaluable certified intersection curve whose source surface
/// parameterizations are not regular across its complete parameter domain.
public enum CertifiedIntersectionCurve3D: Hashable, Sendable {
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        switch self {
        case let .sphereCone(curve):
            try curve.validate(tolerance: tolerance, using: &execution)
        case let .coneCone(curve):
            try curve.validate(tolerance: tolerance, using: &execution)
        case let .coneCylinder(curve):
            try curve.validate(tolerance: tolerance, using: &execution)
        case let .coneTorus(curve):
            try curve.validate(tolerance: tolerance, using: &execution)
        case let .parallelTorusTorus(curve):
            try curve.validate(tolerance: tolerance, using: &execution)
        }
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try point(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.consumeWork(1)
        return switch self {
        case let .sphereCone(curve):
            try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
        case let .coneCone(curve):
            try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
        case let .coneCylinder(curve):
            try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
        case let .coneTorus(curve):
            try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
        case let .parallelTorusTorus(curve):
            try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
        }
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try differential(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> DifferentialGeometry {
        try execution.consumeWork(1)
        switch self {
        case let .sphereCone(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .coneCone(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .coneCylinder(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .coneTorus(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .parallelTorusTorus(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        }
    }

    package func boundingBox(
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try boundingBox(tolerance: tolerance, using: &execution)
    }

    package func boundingBox(
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
        try execution.consumeWork(1)
        return switch self {
        case let .sphereCone(curve):
            try curve.boundingBox(tolerance: tolerance, using: &execution)
        case let .coneCone(curve):
            try curve.boundingBox(tolerance: tolerance, using: &execution)
        case let .coneCylinder(curve):
            try curve.boundingBox(tolerance: tolerance, using: &execution)
        case let .coneTorus(curve):
            try curve.boundingBox(tolerance: tolerance, using: &execution)
        case let .parallelTorusTorus(curve):
            try curve.boundingBox(tolerance: tolerance, using: &execution)
        }
    }

    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameter(on: surface, atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }

    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.consumeWork(1)
        switch self {
        case let .sphereCone(curve):
            return try curve.parameter(
                on: surface,
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
        case let .coneCone(curve):
            return try curve.parameter(
                on: surface,
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
        case let .coneCylinder(curve):
            return try curve.parameter(
                on: surface,
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
        case let .coneTorus(curve):
            return try curve.parameter(
                on: surface,
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
        case let .parallelTorusTorus(curve):
            return try curve.parameter(
                on: surface,
                atNormalizedFraction: fraction,
                tolerance: tolerance
            , using: &execution)
        }
    }
}

#if !hasFeature(Embedded)
extension CertifiedIntersectionCurve3D: Codable {}
#endif
