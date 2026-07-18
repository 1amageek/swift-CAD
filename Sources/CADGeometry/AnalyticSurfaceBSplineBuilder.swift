import Foundation
import CADCore

struct AnalyticSurfaceBSplineBuilder {
    private struct CircleControlPoint {
        let x: Double
        let y: Double
        let weight: Double
    }

    private struct MeridianControlPoint {
        let radial: Double
        let axial: Double
        let weight: Double
    }

    func surface(
        for analytic: CanonicalAnalyticSurface,
        boundedBy reference: BSplineSurface3D,
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        try tolerance.validate()
        try reference.validate(tolerance: tolerance)
        guard periodicSeamOffset.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The analytic NURBS periodic seam offset must be finite."
            )
        }

        let result: BSplineSurface3D
        switch analytic {
        case let .cylinder(cylinder):
            result = try cylinderSurface(
                cylinder,
                boundedBy: reference,
                periodicSeamOffset: periodicSeamOffset,
                tolerance: tolerance
            )
        case let .cone(cone):
            result = try coneSurface(
                cone,
                boundedBy: reference,
                periodicSeamOffset: periodicSeamOffset,
                tolerance: tolerance
            )
        case let .sphere(sphere):
            result = try sphereSurface(
                sphere,
                periodicSeamOffset: periodicSeamOffset,
                tolerance: tolerance
            )
        case let .torus(torus):
            result = try torusSurface(
                torus,
                periodicSeamOffset: periodicSeamOffset,
                tolerance: tolerance
            )
        case .plane, .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "The requested analytic surface cannot be represented by the bounded analytic NURBS builder."
            )
        }
        try result.validate(tolerance: tolerance)
        return result
    }

    private func cylinderSurface(
        _ cylinder: CanonicalAnalyticSurface.Cylinder,
        boundedBy reference: BSplineSurface3D,
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        let basis = try analyticOrthonormalBasis(
            cylinder.axis,
            tolerance: tolerance
        )
        let bounds = expandedAxialBounds(
            points: reference.controlPoints.flatMap { $0 },
            origin: cylinder.origin,
            axis: cylinder.axis,
            scale: 1.0,
            tolerance: tolerance
        )
        let controls = circleControlPoints(seamOffset: periodicSeamOffset)
        let rows = [bounds.lower, bounds.upper].map { axial in
            controls.map { control in
                cylinder.origin
                    + basis.u * (control.x * cylinder.radius)
                    + basis.v * (control.y * cylinder.radius)
                    + cylinder.axis * axial
            }
        }
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 1,
            uKnots: circleKnots,
            vKnots: [bounds.lower, bounds.lower, bounds.upper, bounds.upper],
            controlPoints: rows,
            weights: [controls.map(\.weight), controls.map(\.weight)]
        )
    }

    private func coneSurface(
        _ cone: CanonicalAnalyticSurface.Cone,
        boundedBy reference: BSplineSurface3D,
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        let basis = try analyticOrthonormalBasis(
            cone.axis,
            tolerance: tolerance
        )
        let cosine = cos(cone.halfAngle)
        let sine = sin(cone.halfAngle)
        let bounds = expandedAxialBounds(
            points: reference.controlPoints.flatMap { $0 },
            origin: cone.apex,
            axis: cone.axis,
            scale: 1.0 / cosine,
            tolerance: tolerance
        )
        let controls = circleControlPoints(seamOffset: periodicSeamOffset)
        let rows = [bounds.lower, bounds.upper].map { slant in
            controls.map { control in
                cone.apex
                    + cone.axis * (slant * cosine)
                    + basis.u * (control.x * slant * sine)
                    + basis.v * (control.y * slant * sine)
            }
        }
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 1,
            uKnots: circleKnots,
            vKnots: [bounds.lower, bounds.lower, bounds.upper, bounds.upper],
            controlPoints: rows,
            weights: [controls.map(\.weight), controls.map(\.weight)]
        )
    }

    private func sphereSurface(
        _ sphere: CanonicalAnalyticSurface.Sphere,
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        let basis = try analyticOrthonormalBasis(
            .unitZ,
            tolerance: tolerance
        )
        let circles = circleControlPoints(seamOffset: periodicSeamOffset)
        let meridian = sphereMeridianControlPoints
        let rows = meridian.map { latitude in
            circles.map { longitude in
                sphere.center
                    + basis.u * (longitude.x * latitude.radial * sphere.radius)
                    + basis.v * (longitude.y * latitude.radial * sphere.radius)
                    + Vector3D.unitZ * (latitude.axial * sphere.radius)
            }
        }
        let weights = meridian.map { latitude in
            circles.map { $0.weight * latitude.weight }
        }
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: circleKnots,
            vKnots: sphereMeridianKnots,
            controlPoints: rows,
            weights: weights
        )
    }

    private func torusSurface(
        _ torus: CanonicalAnalyticSurface.Torus,
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        let basis = try analyticOrthonormalBasis(
            torus.axis,
            tolerance: tolerance
        )
        let majorControls = circleControlPoints(seamOffset: periodicSeamOffset)
        let minorControls = circleControlPoints(seamOffset: periodicSeamOffset)
        let rows = minorControls.map { minor in
            majorControls.map { major in
                torus.center
                    + basis.u * (
                        major.x * (torus.majorRadius + torus.minorRadius * minor.x)
                    )
                    + basis.v * (
                        major.y * (torus.majorRadius + torus.minorRadius * minor.x)
                    )
                    + torus.axis * (torus.minorRadius * minor.y)
            }
        }
        let weights = minorControls.map { minor in
            majorControls.map { $0.weight * minor.weight }
        }
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: circleKnots,
            vKnots: circleKnots,
            controlPoints: rows,
            weights: weights
        )
    }

    private func expandedAxialBounds(
        points: [Point3D],
        origin: Point3D,
        axis: Vector3D,
        scale: Double,
        tolerance: ModelingTolerance
    ) -> (lower: Double, upper: Double) {
        let values = points.map { ($0 - origin).dot(axis) * scale }
        let lower = values.min() ?? 0.0
        let upper = values.max() ?? 0.0
        let span = upper - lower
        let padding = max(tolerance.distance * 8.0, span * 1.0e-8)
        return (lower - padding, upper + padding)
    }

    private func circleControlPoints(seamOffset: Double) -> [CircleControlPoint] {
        let diagonalWeight = sqrt(0.5)
        let canonical = [
            CircleControlPoint(x: 1.0, y: 0.0, weight: 1.0),
            CircleControlPoint(x: 1.0, y: 1.0, weight: diagonalWeight),
            CircleControlPoint(x: 0.0, y: 1.0, weight: 1.0),
            CircleControlPoint(x: -1.0, y: 1.0, weight: diagonalWeight),
            CircleControlPoint(x: -1.0, y: 0.0, weight: 1.0),
            CircleControlPoint(x: -1.0, y: -1.0, weight: diagonalWeight),
            CircleControlPoint(x: 0.0, y: -1.0, weight: 1.0),
            CircleControlPoint(x: 1.0, y: -1.0, weight: diagonalWeight),
            CircleControlPoint(x: 1.0, y: 0.0, weight: 1.0),
        ]
        let cosine = cos(seamOffset)
        let sine = sin(seamOffset)
        return canonical.map {
            CircleControlPoint(
                x: $0.x * cosine - $0.y * sine,
                y: $0.x * sine + $0.y * cosine,
                weight: $0.weight
            )
        }
    }

    private var sphereMeridianControlPoints: [MeridianControlPoint] {
        let diagonalWeight = sqrt(0.5)
        return [
            MeridianControlPoint(radial: 0.0, axial: -1.0, weight: 1.0),
            MeridianControlPoint(radial: 1.0, axial: -1.0, weight: diagonalWeight),
            MeridianControlPoint(radial: 1.0, axial: 0.0, weight: 1.0),
            MeridianControlPoint(radial: 1.0, axial: 1.0, weight: diagonalWeight),
            MeridianControlPoint(radial: 0.0, axial: 1.0, weight: 1.0),
        ]
    }

    private var circleKnots: [Double] {
        [0.0, 0.0, 0.0, 1.0, 1.0, 2.0, 2.0, 3.0, 3.0, 4.0, 4.0, 4.0]
    }

    private var sphereMeridianKnots: [Double] {
        [0.0, 0.0, 0.0, 1.0, 1.0, 2.0, 2.0, 2.0]
    }
}
