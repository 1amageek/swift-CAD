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
        return try surface(
            for: analytic,
            boundedByPoints: reference.controlPoints.flatMap { $0 },
            periodicSeamOffset: periodicSeamOffset,
            tolerance: tolerance
        )
    }

    func surface(
        for analytic: CanonicalAnalyticSurface,
        boundedByPoints points: [Point3D],
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        try tolerance.validate()
        guard points.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An exact analytic NURBS conversion requires a nonempty bounding point set."
            )
        }
        for point in points {
            try point.validate()
        }
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
        case let .plane(plane):
            result = try planeSurface(
                plane,
                boundedBy: points,
                tolerance: tolerance
            )
        case let .cylinder(cylinder):
            result = try cylinderSurface(
                cylinder,
                boundedBy: points,
                periodicSeamOffset: periodicSeamOffset,
                tolerance: tolerance
            )
        case let .cone(cone):
            result = try coneSurface(
                cone,
                boundedBy: points,
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
        case .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The analytic NURBS builder received a non-analytic surface."
            )
        }
        try result.validate(tolerance: tolerance)
        return result
    }

    private func planeSurface(
        _ plane: CanonicalAnalyticSurface.Plane,
        boundedBy points: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        let basis = try analyticOrthonormalBasis(plane.normal, tolerance: tolerance)
        let parameters = points.map { point in
            let offset = point - plane.origin
            return Point2D(x: offset.dot(basis.u), y: offset.dot(basis.v))
        }
        let rawULower = parameters.map(\.x).min() ?? 0.0
        let rawUUpper = parameters.map(\.x).max() ?? 0.0
        let rawVLower = parameters.map(\.y).min() ?? 0.0
        let rawVUpper = parameters.map(\.y).max() ?? 0.0
        let characteristicLength = max(
            rawUUpper - rawULower,
            rawVUpper - rawVLower,
            points.map { ($0 - plane.origin).length }.max() ?? 0.0,
            1.0
        )
        let padding = max(
            tolerance.distance * 32.0,
            characteristicLength * 1.0e-8,
            Double.ulpOfOne * characteristicLength * 4_096.0
        )
        let uLower = rawULower - padding
        let uUpper = rawUUpper + padding
        let vLower = rawVLower - padding
        let vUpper = rawVUpper + padding
        let point: (Double, Double) -> Point3D = { u, v in
            plane.origin + basis.u * u + basis.v * v
        }
        return BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [uLower, uLower, uUpper, uUpper],
            vKnots: [vLower, vLower, vUpper, vUpper],
            controlPoints: [
                [point(uLower, vLower), point(uUpper, vLower)],
                [point(uLower, vUpper), point(uUpper, vUpper)],
            ]
        )
    }

    private func cylinderSurface(
        _ cylinder: CanonicalAnalyticSurface.Cylinder,
        boundedBy points: [Point3D],
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        let basis = try analyticOrthonormalBasis(
            cylinder.axis,
            tolerance: tolerance
        )
        let bounds = expandedAxialBounds(
            points: points,
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
        boundedBy points: [Point3D],
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
            points: points,
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
