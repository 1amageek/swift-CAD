#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try surface(for: analytic, boundedBy: reference, periodicSeamOffset: periodicSeamOffset, tolerance: tolerance, using: &execution)
    }


    func surface(
        for analytic: CanonicalAnalyticSurface,
        boundedBy reference: BSplineSurface3D,
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BSplineSurface3D {
        try execution.checkpoint()
        let result = try surfaceImplementation(for: analytic, boundedBy: reference, periodicSeamOffset: periodicSeamOffset, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func surfaceImplementation(
        for analytic: CanonicalAnalyticSurface,
        boundedBy reference: BSplineSurface3D,
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BSplineSurface3D {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try tolerance.validate()
        try reference.validate(tolerance: tolerance, using: &execution)
        let count = try reference.controlPoints.reduce(0) { try exactScalarCount($0, $1.count) }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Point3D.self))
        var points: [Point3D] = []
        points.reserveCapacity(count)
        for row in reference.controlPoints {
            try execution.consumeWork(row.count)
            points.append(contentsOf: row)
        }
        return try surface(
            for: analytic,
            boundedByPoints: points,
            periodicSeamOffset: periodicSeamOffset,
            tolerance: tolerance
        , using: &execution)
    }

    func surface(
        for analytic: CanonicalAnalyticSurface,
        boundedByPoints points: [Point3D],
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try surface(for: analytic, boundedByPoints: points, periodicSeamOffset: periodicSeamOffset, tolerance: tolerance, using: &execution)
    }


    func surface(
        for analytic: CanonicalAnalyticSurface,
        boundedByPoints points: [Point3D],
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BSplineSurface3D {
        try execution.checkpoint()
        let result = try surfaceImplementation(for: analytic, boundedByPoints: points, periodicSeamOffset: periodicSeamOffset, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func surfaceImplementation(
        for analytic: CanonicalAnalyticSurface,
        boundedByPoints points: [Point3D],
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BSplineSurface3D {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
            , using: &execution)
        case let .cylinder(cylinder):
            result = try cylinderSurface(
                cylinder,
                boundedBy: points,
                periodicSeamOffset: periodicSeamOffset,
                tolerance: tolerance
            , using: &execution)
        case let .cone(cone):
            result = try coneSurface(
                cone,
                boundedBy: points,
                periodicSeamOffset: periodicSeamOffset,
                tolerance: tolerance
            , using: &execution)
        case let .sphere(sphere):
            result = try sphereSurface(
                sphere,
                periodicSeamOffset: periodicSeamOffset,
                tolerance: tolerance
            , using: &execution)
        case let .torus(torus):
            result = try torusSurface(
                torus,
                periodicSeamOffset: periodicSeamOffset,
                tolerance: tolerance
            , using: &execution)
        case .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The analytic NURBS builder received a non-analytic surface."
            )
        }
        try result.validate(tolerance: tolerance, using: &execution)
        return result
    }

    private func planeSurface<A: ExactScalarAdmission & ~Copyable>(
        _ plane: CanonicalAnalyticSurface.Plane,
        boundedBy points: [Point3D],
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> BSplineSurface3D {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 8, of: Double.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: Point3D.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [Point3D].self))
        try execution.checkpoint()
        try execution.consumeWork(1)
        let basis = try OriginalStoredPlaneBasis.basis(plane.normal,tolerance:tolerance)
        let parameters = (try CertifiedAnalyticCurveEvaluation.map(points, using: &execution) { point, execution in
            let offset = point - plane.origin
            return Point2D(x: offset.dot(basis.u), y: offset.dot(basis.v))
         })
        let rawULower = (try CertifiedAnalyticCurveEvaluation.map(parameters, using: &execution) { element, execution in  element.x  }).min() ?? 0.0
        let rawUUpper = (try CertifiedAnalyticCurveEvaluation.map(parameters, using: &execution) { element, execution in  element.x  }).max() ?? 0.0
        let rawVLower = (try CertifiedAnalyticCurveEvaluation.map(parameters, using: &execution) { element, execution in  element.y  }).min() ?? 0.0
        let rawVUpper = (try CertifiedAnalyticCurveEvaluation.map(parameters, using: &execution) { element, execution in  element.y  }).max() ?? 0.0
        let characteristicLength = max(
            rawUUpper - rawULower,
            rawVUpper - rawVLower,
            (try CertifiedAnalyticCurveEvaluation.map(points, using: &execution) { element, execution in  (element - plane.origin).length  }).max() ?? 0.0,
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

    private func cylinderSurface<A: ExactScalarAdmission & ~Copyable>(
        _ cylinder: CanonicalAnalyticSurface.Cylinder,
        boundedBy points: [Point3D],
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> BSplineSurface3D {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: Double.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [Double].self))
        try execution.checkpoint()
        try execution.consumeWork(1)
        let basis = try analyticOrthonormalBasis(
            cylinder.axis,
            tolerance: tolerance
        )
        let bounds = (try expandedAxialBounds(
            points: points,
            origin: cylinder.origin,
            axis: cylinder.axis,
            scale: 1.0,
            tolerance: tolerance
        , using: &execution))
        let controls = (try circleControlPoints(seamOffset: periodicSeamOffset, using: &execution))
        let rows = (try CertifiedAnalyticCurveEvaluation.map([bounds.lower, bounds.upper], using: &execution) { axial, execution in
            (try CertifiedAnalyticCurveEvaluation.map(controls, using: &execution) { control, execution in
                cylinder.origin
                    + basis.u * (control.x * cylinder.radius)
                    + basis.v * (control.y * cylinder.radius)
                    + cylinder.axis * axial
             })
         })
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 1,
            uKnots: try circleKnots(using: &execution),
            vKnots: [bounds.lower, bounds.lower, bounds.upper, bounds.upper],
            controlPoints: rows,
            weights: [(try CertifiedAnalyticCurveEvaluation.map(controls, using: &execution) { element, execution in  element.weight  }), (try CertifiedAnalyticCurveEvaluation.map(controls, using: &execution) { element, execution in  element.weight  })]
        )
    }

    private func coneSurface<A: ExactScalarAdmission & ~Copyable>(
        _ cone: CanonicalAnalyticSurface.Cone,
        boundedBy points: [Point3D],
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> BSplineSurface3D {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: Double.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [Double].self))
        try execution.checkpoint()
        try execution.consumeWork(1)
        let basis = try analyticOrthonormalBasis(
            cone.axis,
            tolerance: tolerance
        )
        let cosine = cos(cone.halfAngle)
        let sine = sin(cone.halfAngle)
        let bounds = (try expandedAxialBounds(
            points: points,
            origin: cone.apex,
            axis: cone.axis,
            scale: 1.0 / cosine,
            tolerance: tolerance
        , using: &execution))
        let controls = (try circleControlPoints(seamOffset: periodicSeamOffset, using: &execution))
        let rows = (try CertifiedAnalyticCurveEvaluation.map([bounds.lower, bounds.upper], using: &execution) { slant, execution in
            (try CertifiedAnalyticCurveEvaluation.map(controls, using: &execution) { control, execution in
                cone.apex
                    + cone.axis * (slant * cosine)
                    + basis.u * (control.x * slant * sine)
                    + basis.v * (control.y * slant * sine)
             })
         })
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 1,
            uKnots: try circleKnots(using: &execution),
            vKnots: [bounds.lower, bounds.lower, bounds.upper, bounds.upper],
            controlPoints: rows,
            weights: [(try CertifiedAnalyticCurveEvaluation.map(controls, using: &execution) { element, execution in  element.weight  }), (try CertifiedAnalyticCurveEvaluation.map(controls, using: &execution) { element, execution in  element.weight  })]
        )
    }

    private func sphereSurface<A: ExactScalarAdmission & ~Copyable>(
        _ sphere: CanonicalAnalyticSurface.Sphere,
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> BSplineSurface3D {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let basis = try analyticOrthonormalBasis(
            .unitZ,
            tolerance: tolerance
        )
        let circles = (try circleControlPoints(seamOffset: periodicSeamOffset, using: &execution))
        let meridian = try sphereMeridianControlPoints(using: &execution)
        let rows = (try CertifiedAnalyticCurveEvaluation.map(meridian, using: &execution) { latitude, execution in
            (try CertifiedAnalyticCurveEvaluation.map(circles, using: &execution) { longitude, execution in
                sphere.center
                    + basis.u * (longitude.x * latitude.radial * sphere.radius)
                    + basis.v * (longitude.y * latitude.radial * sphere.radius)
                    + Vector3D.unitZ * (latitude.axial * sphere.radius)
             })
         })
        let weights = (try CertifiedAnalyticCurveEvaluation.map(meridian, using: &execution) { latitude, execution in
            (try CertifiedAnalyticCurveEvaluation.map(circles, using: &execution) { element, execution in  element.weight * latitude.weight  })
         })
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: try circleKnots(using: &execution),
            vKnots: try sphereMeridianKnots(using: &execution),
            controlPoints: rows,
            weights: weights
        )
    }

    private func torusSurface<A: ExactScalarAdmission & ~Copyable>(
        _ torus: CanonicalAnalyticSurface.Torus,
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> BSplineSurface3D {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let basis = try analyticOrthonormalBasis(
            torus.axis,
            tolerance: tolerance
        )
        let majorControls = (try circleControlPoints(seamOffset: periodicSeamOffset, using: &execution))
        let minorControls = (try circleControlPoints(seamOffset: periodicSeamOffset, using: &execution))
        let rows = (try CertifiedAnalyticCurveEvaluation.map(minorControls, using: &execution) { minor, execution in
            (try CertifiedAnalyticCurveEvaluation.map(majorControls, using: &execution) { major, execution in
                torus.center
                    + basis.u * (
                        major.x * (torus.majorRadius + torus.minorRadius * minor.x)
                    )
                    + basis.v * (
                        major.y * (torus.majorRadius + torus.minorRadius * minor.x)
                    )
                    + torus.axis * (torus.minorRadius * minor.y)
             })
         })
        let weights = (try CertifiedAnalyticCurveEvaluation.map(minorControls, using: &execution) { minor, execution in
            (try CertifiedAnalyticCurveEvaluation.map(majorControls, using: &execution) { element, execution in  element.weight * minor.weight  })
         })
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: try circleKnots(using: &execution),
            vKnots: try circleKnots(using: &execution),
            controlPoints: rows,
            weights: weights
        )
    }

    private func expandedAxialBounds<A: ExactScalarAdmission & ~Copyable>(
        points: [Point3D],
        origin: Point3D,
        axis: Vector3D,
        scale: Double,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> (lower: Double, upper: Double) {
        let values = (try CertifiedAnalyticCurveEvaluation.map(points, using: &execution) { element, execution in  (element - origin).dot(axis) * scale  })
        let lower = values.min() ?? 0.0
        let upper = values.max() ?? 0.0
        let span = upper - lower
        let padding = max(tolerance.distance * 8.0, span * 1.0e-8)
        return (lower - padding, upper + padding)
    }

    private func circleControlPoints<A: ExactScalarAdmission & ~Copyable>(seamOffset: Double, using execution: inout A) throws -> [CircleControlPoint] {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 9, of: CircleControlPoint.self))
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
        return (try CertifiedAnalyticCurveEvaluation.map(canonical, using: &execution) { element, execution in 
            CircleControlPoint(
                x: element.x * cosine - element.y * sine,
                y: element.x * sine + element.y * cosine,
                weight: element.weight
            )
         })
    }

    private func sphereMeridianControlPoints<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> [MeridianControlPoint] {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 5, of: MeridianControlPoint.self))
        try execution.consumeWork(5)
        let diagonalWeight = sqrt(0.5)
        return [
            MeridianControlPoint(radial: 0.0, axial: -1.0, weight: 1.0),
            MeridianControlPoint(radial: 1.0, axial: -1.0, weight: diagonalWeight),
            MeridianControlPoint(radial: 1.0, axial: 0.0, weight: 1.0),
            MeridianControlPoint(radial: 1.0, axial: 1.0, weight: diagonalWeight),
            MeridianControlPoint(radial: 0.0, axial: 1.0, weight: 1.0),
        ]
    }

    private func circleKnots<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> [Double] {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 12, of: Double.self))
        try execution.consumeWork(12)
        return [0.0, 0.0, 0.0, 1.0, 1.0, 2.0, 2.0, 3.0, 3.0, 4.0, 4.0, 4.0]
    }

    private func sphereMeridianKnots<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> [Double] {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 8, of: Double.self))
        try execution.consumeWork(8)
        return [0.0, 0.0, 0.0, 1.0, 1.0, 2.0, 2.0, 2.0]
    }
}
