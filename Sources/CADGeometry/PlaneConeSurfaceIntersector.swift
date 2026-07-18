import Foundation
import CADCore

struct PlaneConeSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
        cone: CanonicalAnalyticSurface.Cone,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let basis = try analyticOrthonormalBasis(plane.normal, tolerance: tolerance)
        let cosineSquared = pow(cos(cone.halfAngle), 2.0)
        let originOffset = plane.origin - cone.apex
        let a00 = quadraticForm(
            basis.u,
            basis.u,
            axis: cone.axis,
            cosineSquared: cosineSquared
        )
        let a01 = quadraticForm(
            basis.u,
            basis.v,
            axis: cone.axis,
            cosineSquared: cosineSquared
        )
        let a11 = quadraticForm(
            basis.v,
            basis.v,
            axis: cone.axis,
            cosineSquared: cosineSquared
        )
        let b0 = quadraticForm(
            basis.u,
            originOffset,
            axis: cone.axis,
            cosineSquared: cosineSquared
        )
        let b1 = quadraticForm(
            basis.v,
            originOffset,
            axis: cone.axis,
            cosineSquared: cosineSquared
        )
        let determinant = a00 * a11 - a01 * a01
        let coefficientScale = max(1.0, max(abs(a00), max(abs(a01), abs(a11))))
        let determinantTolerance = max(
            tolerance.angle * coefficientScale * coefficientScale,
            Double.ulpOfOne * 64.0
        )
        let containsApex = abs((cone.apex - plane.origin).dot(plane.normal)) <= tolerance.distance

        if determinant < -determinantTolerance {
            guard containsApex else {
                throw unsupportedSection("hyperbolic", tolerance: tolerance)
            }
            return try generatorLines(
                apex: cone.apex,
                basisU: basis.u,
                basisV: basis.v,
                a00: a00,
                a01: a01,
                a11: a11,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        }
        if abs(determinant) <= determinantTolerance {
            guard containsApex else {
                throw unsupportedSection("parabolic", tolerance: tolerance)
            }
            return try generatorLines(
                apex: cone.apex,
                basisU: basis.u,
                basisV: basis.v,
                a00: a00,
                a01: a01,
                a11: a11,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        }

        let centerU = (a01 * b1 - a11 * b0) / determinant
        let centerV = (a01 * b0 - a00 * b1) / determinant
        let center = plane.origin + basis.u * centerU + basis.v * centerV
        let centeredOffset = center - cone.apex
        let centerValue = quadraticForm(
            centeredOffset,
            centeredOffset,
            axis: cone.axis,
            cosineSquared: cosineSquared
        )
        let discriminant = sqrt(max(0.0, pow(a00 - a11, 2.0) + 4.0 * a01 * a01))
        let firstEigenvalue = (a00 + a11 + discriminant) * 0.5
        let secondEigenvalue = (a00 + a11 - discriminant) * 0.5
        guard abs(firstEigenvalue) > determinantTolerance,
              abs(secondEigenvalue) > determinantTolerance else {
            throw unsupportedSection("degenerate", tolerance: tolerance)
        }
        let firstRadiusSquared = -centerValue / firstEigenvalue
        let secondRadiusSquared = -centerValue / secondEigenvalue
        let squaredTolerance = tolerance.distance * tolerance.distance
        guard firstRadiusSquared >= -squaredTolerance,
              secondRadiusSquared >= -squaredTolerance else {
            return []
        }
        if max(firstRadiusSquared, secondRadiusSquared) <= squaredTolerance {
            return [try verifier.point(
                center,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )]
        }

        let firstEigenvector = try eigenvector(
            a00: a00,
            a01: a01,
            eigenvalue: firstEigenvalue,
            basisU: basis.u,
            basisV: basis.v,
            tolerance: tolerance
        )
        let secondEigenvector = try plane.normal.cross(firstEigenvector).normalized(
            tolerance: tolerance.distance
        )
        let firstRadius = sqrt(max(0.0, firstRadiusSquared))
        let secondRadius = sqrt(max(0.0, secondRadiusSquared))
        let curve: Curve3D
        if abs(firstRadius - secondRadius) <= tolerance.distance {
            curve = .circle(Circle3D(
                center: center,
                normal: plane.normal,
                radius: max(firstRadius, secondRadius)
            ))
        } else {
            let firstIsMajor = firstRadius > secondRadius
            curve = .analytic(.ellipse(
                center: center,
                normal: plane.normal,
                majorAxis: firstIsMajor ? firstEigenvector : secondEigenvector,
                majorRadius: max(firstRadius, secondRadius),
                minorRadius: min(firstRadius, secondRadius)
            ))
        }
        return [try verifier.curve(
            curve,
            kind: .transverse,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
            tolerance: tolerance
        )]
    }

    private func quadraticForm(
        _ first: Vector3D,
        _ second: Vector3D,
        axis: Vector3D,
        cosineSquared: Double
    ) -> Double {
        axis.dot(first) * axis.dot(second) - cosineSquared * first.dot(second)
    }

    private func generatorLines(
        apex: Point3D,
        basisU: Vector3D,
        basisV: Vector3D,
        a00: Double,
        a01: Double,
        a11: Double,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let coefficientTolerance = max(tolerance.angle, Double.ulpOfOne * 64.0)
        var directions: [Vector3D] = []
        if abs(a11) > coefficientTolerance {
            let root = sqrt(max(0.0, a01 * a01 - a00 * a11))
            for slope in [(-a01 - root) / a11, (-a01 + root) / a11] {
                directions.append(try (basisU + basisV * slope).normalized(
                    tolerance: tolerance.distance
                ))
            }
        } else if abs(a01) > coefficientTolerance {
            directions.append(basisV)
            directions.append(try (basisU * (2.0 * a01) - basisV * a00).normalized(
                tolerance: tolerance.distance
            ))
        } else {
            directions.append(basisV)
        }

        var uniqueDirections: [Vector3D] = []
        for direction in directions where !uniqueDirections.contains(where: {
            abs($0.dot(direction)) >= 1.0 - tolerance.angle
        }) {
            uniqueDirections.append(direction)
        }
        let kind: CurveSurfaceIntersectionKind = uniqueDirections.count == 1 ? .tangent : .transverse
        return try uniqueDirections.map { direction in
            try verifier.curve(
                .line(Line3D(origin: apex, direction: direction)),
                kind: kind,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: SurfaceSurfaceIntersectionVerifier.lineSamples,
                tolerance: tolerance
            )
        }
    }

    private func eigenvector(
        a00: Double,
        a01: Double,
        eigenvalue: Double,
        basisU: Vector3D,
        basisV: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        let localX: Double
        let localY: Double
        if abs(a01) > tolerance.angle {
            localX = a01
            localY = eigenvalue - a00
        } else if abs(a00 - eigenvalue) <= tolerance.angle {
            localX = 1.0
            localY = 0.0
        } else {
            localX = 0.0
            localY = 1.0
        }
        return try (basisU * localX + basisV * localY).normalized(
            tolerance: tolerance.distance
        )
    }

    private func unsupportedSection(
        _ kind: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message: "Plane-cone \(kind) sections are not representable by the current exact curve contract."
        )
    }
}
