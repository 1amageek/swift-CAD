import Foundation
import CADCore
import CADGeometry
import CADIR

enum ExactSurfaceParameterCodec {
    static func encode(
        _ parameter: SurfaceParameterProjection,
        on surface: Surface3D,
        unit: LengthUnit,
        convention: ExactSurfaceParameterConvention = .step
    ) -> SurfaceParameter {
        encode(
            SurfaceParameter(u: parameter.u, v: parameter.v),
            on: surface,
            unit: unit,
            convention: convention
        )
    }

    static func encode(
        _ parameter: SurfaceParameter,
        on surface: Surface3D,
        unit: LengthUnit,
        convention: ExactSurfaceParameterConvention = .step
    ) -> SurfaceParameter {
        switch surface {
        case .plane:
            return SurfaceParameter(
                u: unit.fromInternal(parameter.u),
                v: unit.fromInternal(parameter.v)
            )
        case .cylinder:
            return SurfaceParameter(u: parameter.u, v: unit.fromInternal(parameter.v))
        case let .analytic(analytic):
            switch analytic {
            case .plane:
                return SurfaceParameter(
                    u: unit.fromInternal(parameter.u),
                    v: unit.fromInternal(parameter.v)
                )
            case .cylinder:
                return SurfaceParameter(u: parameter.u, v: unit.fromInternal(parameter.v))
            case let .cone(_, _, halfAngle):
                return SurfaceParameter(
                    u: parameter.u,
                    v: unit.fromInternal(parameter.v * cos(halfAngle))
                )
            case .sphere:
                return SurfaceParameter(u: parameter.u, v: parameter.v)
            case .torus:
                return convention == .iges
                    ? SurfaceParameter(u: parameter.v, v: parameter.u)
                    : SurfaceParameter(u: parameter.u, v: parameter.v)
            }
        case .bSpline:
            return SurfaceParameter(u: parameter.u, v: parameter.v)
        }
    }

    static func decode(
        _ parameter: SurfaceParameter,
        on surface: Surface3D,
        unit: LengthUnit,
        tolerance: ModelingTolerance,
        convention: ExactSurfaceParameterConvention = .step
    ) throws -> SurfaceParameter {
        try tolerance.validate()
        switch surface {
        case .plane:
            return SurfaceParameter(
                u: unit.toInternal(parameter.u),
                v: unit.toInternal(parameter.v)
            )
        case .cylinder:
            return SurfaceParameter(u: parameter.u, v: unit.toInternal(parameter.v))
        case let .analytic(analytic):
            switch analytic {
            case .plane:
                return SurfaceParameter(
                    u: unit.toInternal(parameter.u),
                    v: unit.toInternal(parameter.v)
                )
            case .cylinder:
                return SurfaceParameter(u: parameter.u, v: unit.toInternal(parameter.v))
            case let .cone(_, _, halfAngle):
                let cosine = cos(halfAngle)
                guard cosine > tolerance.angle else {
                    throw KernelError(
                        phase: .exchange,
                        code: .invalidInput,
                        tolerance: tolerance,
                        message: "Cone parameter conversion requires a finite non-right half angle."
                    )
                }
                return SurfaceParameter(
                    u: parameter.u,
                    v: unit.toInternal(parameter.v) / cosine
                )
            case .sphere:
                return parameter
            case .torus:
                return convention == .iges
                    ? SurfaceParameter(u: parameter.v, v: parameter.u)
                    : parameter
            }
        case .bSpline:
            return parameter
        }
    }

    static func encodedTolerance(
        on surface: Surface3D,
        unit: LengthUnit,
        tolerance: ModelingTolerance
    ) -> Double {
        switch surface {
        case .plane, .cylinder:
            return max(tolerance.angle, unit.fromInternal(tolerance.distance))
        case let .analytic(analytic):
            switch analytic {
            case .plane, .cylinder, .cone:
                return max(tolerance.angle, unit.fromInternal(tolerance.distance))
            case .sphere, .torus:
                return tolerance.angle
            }
        case .bSpline:
            return max(tolerance.angle, tolerance.distance)
        }
    }
}
