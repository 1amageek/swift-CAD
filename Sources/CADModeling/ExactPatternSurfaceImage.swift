import CADCore
import CADGeometry
import Foundation

package struct ExactPatternSurfaceImage: Sendable {
    package let surface: Surface3D
    package let reversesFaceOrientation: Bool

    private let parameterMapping: ParameterMapping
    private let sourceSurface: Surface3D
    private let transform: ExactPatternTransform

    private enum ParameterMapping: Sendable {
        case affine(ParameterAffineTransform)
        case sphericalGreatCircleOnly
    }

    private typealias ParameterAffineTransform = SurfaceParameterAffineTransform

    package init(
        source: Surface3D,
        transform: ExactPatternTransform,
        tolerance: ModelingTolerance
    ) throws {
        sourceSurface = source
        self.transform = transform
        surface = try transform.applying(to: source, tolerance: tolerance)
        if let mapping = try transform.parameterAffineTransform(
            from: source,
            to: surface,
            tolerance: tolerance
        ) {
            parameterMapping = .affine(mapping)
        } else {
            guard case .analytic(.sphere) = source else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A pattern surface image has no exact parameter-chart mapping."
                )
            }
            parameterMapping = .sphericalGreatCircleOnly
        }
        if case .bSpline = source {
            reversesFaceOrientation = transform.reversesOrientation
        } else {
            reversesFaceOrientation = false
        }
        try surface.validate(tolerance: tolerance)
    }

    package func applying(
        to parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        switch parameterMapping {
        case let .affine(mapping):
            return try applying(
                mapping,
                to: parameterCurve,
                tolerance: tolerance
            )
        case .sphericalGreatCircleOnly:
            return try applyingToSphericalGreatCircle(
                parameterCurve,
                tolerance: tolerance
            )
        }
    }

    private func applying(
        _ mapping: ParameterAffineTransform,
        to parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        switch parameterCurve {
        case let .affine(origin, direction, startParameter, endParameter):
            return .affine(
                origin: mapping.applying(to: origin),
                direction: mapping.applyingVector(to: direction),
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .constantU(u, vStart, vEnd):
            return .polyline([
                mapping.applying(to: SurfaceParameter(u: u, v: vStart)),
                mapping.applying(to: SurfaceParameter(u: u, v: vEnd)),
            ])
        case let .constantV(v, uStart, uEnd):
            return .polyline([
                mapping.applying(to: SurfaceParameter(u: uStart, v: v)),
                mapping.applying(to: SurfaceParameter(u: uEnd, v: v)),
            ])
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            return .harmonic(
                center: mapping.applying(to: center),
                cosine: mapping.applyingVector(to: cosine),
                sine: mapping.applyingVector(to: sine),
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .polyline(points):
            return .polyline(points.map(mapping.applying(to:)))
        case let .bSpline(curve):
            return .bSpline(BSplineCurve2D(
                degree: curve.degree,
                knots: curve.knots,
                controlPoints: curve.controlPoints.map(mapping.applying(to:)),
                weights: curve.weights
            ))
        case let .projectedAnalytic(projected):
            let transformedCurve = try transform.applying(
                to: projected.curve,
                from: projected.startParameter,
                to: projected.endParameter,
                tolerance: tolerance
            )
            return .projectedAnalytic(try ProjectedAnalyticSurfaceParameterCurve(
                curve: transformedCurve,
                surface: surface,
                startParameter: projected.startParameter,
                endParameter: projected.endParameter,
                tolerance: tolerance
            ))
        case let .sphericalGreatCircle(cosine, sine, startParameter, endParameter):
            return .sphericalGreatCircle(
                cosine: transform.applying(to: cosine),
                sine: transform.applying(to: sine),
                startParameter: startParameter,
                endParameter: endParameter
            )
        case .certifiedImplicit,
             .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .rigidImage, .offsetSurfaceImage:
            return try rigidImage(parameterCurve, tolerance: tolerance)
        case let .periodicTranslation(base, uShift, vShift):
            let mappedShift = mapping.applyingVector(
                to: Point2D(x: uShift, y: vShift)
            )
            return .periodicTranslation(
                base: try applying(mapping, to: base, tolerance: tolerance),
                uShift: mappedShift.x,
                vShift: mappedShift.y
            )
        }
    }

    private func applyingToSphericalGreatCircle(
        _ parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        switch parameterCurve {
        case let .sphericalGreatCircle(cosine, sine, startParameter, endParameter):
            return .sphericalGreatCircle(
                cosine: transform.applying(to: cosine),
                sine: transform.applying(to: sine),
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .periodicTranslation(base, uShift, vShift):
            return .periodicTranslation(
                base: try applyingToSphericalGreatCircle(
                    base,
                    tolerance: tolerance
                ),
                uShift: uShift,
                vShift: vShift
            )
        default:
            return try rigidImage(parameterCurve, tolerance: tolerance)
        }
    }

    private func rigidImage(
        _ parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        .rigidImage(try RigidImageSurfaceParameterCurve(
            source: SurfaceLiftCurve3D(
                surface: sourceSurface,
                parameterCurve: parameterCurve
            ),
            targetSurface: surface,
            transform: transform,
            tolerance: tolerance
        ))
    }

}
