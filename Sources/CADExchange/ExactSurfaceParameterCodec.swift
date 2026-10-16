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
    ) throws -> SurfaceParameter {
        try encode(
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
    ) throws -> SurfaceParameter {
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
        case let .procedural(procedural):
            switch procedural {
            case let .offset(offset):
                return try encode(
                    parameter,
                    on: offset.source,
                    unit: unit,
                    convention: convention
                )
            case .originalImage:
                // The actual primitive writer proves the retained foreign chart against its standard context.
                return parameter
            case .ruled, .rollingBall, .originalRevolution, .originalCoons, .originalAffineWord:
                return parameter
            // FIXME(INCOMPLETE_IMPLEMENTATION): Exact neutral exchange has no chart carrier for these source laws.
            // STEP/IGES encode must refuse until original UV transport and round-trip fidelity are proved.
            case .originalAngularTransport, .originalBoundaryCorrected, .originalPlaneDerivative, .originalDrafted:
                throw unavailableOriginalChart(tolerance: nil)
            }
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
        case let .procedural(procedural):
            switch procedural {
            case let .offset(offset):
                return try decode(
                    parameter,
                    on: offset.source,
                    unit: unit,
                    tolerance: tolerance,
                    convention: convention
                )
            case .originalImage:
                // The actual primitive writer proves the retained foreign chart against its standard context.
                return parameter
            case .ruled, .rollingBall, .originalRevolution, .originalCoons, .originalAffineWord:
                return parameter
            // FIXME(INCOMPLETE_IMPLEMENTATION): Exact neutral exchange has no chart carrier for these source laws.
            // STEP/IGES decode must refuse until original UV transport and round-trip fidelity are proved.
            case .originalAngularTransport, .originalBoundaryCorrected, .originalPlaneDerivative, .originalDrafted:
                throw unavailableOriginalChart(tolerance: tolerance)
            }
        }
    }

    static func encodedTolerance(
        on surface: Surface3D,
        unit: LengthUnit,
        tolerance: ModelingTolerance
    ) throws -> Double {
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
        case let .procedural(procedural):
            switch procedural {
            case let .offset(offset):
                return try encodedTolerance(
                    on: offset.source,
                    unit: unit,
                    tolerance: tolerance
                )
            case .originalImage(let image):
                let native = try encodedTolerance(on: image.source, unit: .meter, tolerance: tolerance)
                return native / min(abs(image.uGain), abs(image.vGain))
            case .ruled, .rollingBall, .originalRevolution, .originalCoons, .originalAffineWord:
                return max(tolerance.angle, tolerance.relative)
            // FIXME(INCOMPLETE_IMPLEMENTATION): Exact neutral exchange cannot assign a schema tolerance to an unissued chart.
            // STEP/IGES publication must refuse until these original charts have faithful standard transport.
            case .originalAngularTransport, .originalBoundaryCorrected, .originalPlaneDerivative, .originalDrafted:
                throw unavailableOriginalChart(tolerance: tolerance)
            }
        }
    }

    private static func unavailableOriginalChart(tolerance: ModelingTolerance?) -> KernelError {
        KernelError(phase: .exchange, code: .unsupportedCapability, tolerance: tolerance,
            message: "This original procedural chart has no faithful STEP/IGES parameter transport.")
    }
}
