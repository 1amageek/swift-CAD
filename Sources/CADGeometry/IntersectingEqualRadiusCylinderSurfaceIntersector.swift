import CADCore

struct IntersectingEqualRadiusCylinderSurfaceIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        first: CanonicalAnalyticSurface.Cylinder,
        second: CanonicalAnalyticSurface.Cylinder,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let firstAxis = try first.axis.normalized(tolerance: tolerance.distance)
        let secondAxis = try second.axis.normalized(tolerance: tolerance.distance)
        guard firstAxis.cross(secondAxis).length > tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Intersecting-cylinder evaluation requires non-parallel axes."
            )
        }

        let radiusResidual = abs(first.radius - second.radius)
        let closestApproach = closestApproach(
            firstOrigin: first.origin,
            firstAxis: firstAxis,
            secondOrigin: second.origin,
            secondAxis: secondAxis
        )
        guard radiusResidual <= tolerance.distance,
              closestApproach.distance <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                residual: max(radiusResidual, closestApproach.distance),
                tolerance: tolerance,
                message: "Non-parallel cylinder-cylinder intersection requires intersecting axes and equal radii."
            )
        }

        let center = closestApproach.firstPoint
            + (closestApproach.secondPoint - closestApproach.firstPoint) * 0.5
        let radius = (first.radius + second.radius) * 0.5
        let axes = canonicalAxes(firstAxis, secondAxis)
        let referenceCylinder = CanonicalAnalyticSurface.Cylinder(
            origin: center,
            axis: axes.first,
            radius: radius
        )
        let planeNormals = try [
            axes.first + axes.second,
            axes.first - axes.second,
        ]
        .map {
            canonicalDirection(try $0.normalized(tolerance: tolerance.angle))
        }
        .sorted(by: lexicographicallyPrecedes)

        return try planeNormals.map { normal in
            let section = try PlaneCylinderSurfaceIntersector().intersections(
                plane: .init(origin: center, normal: normal),
                cylinder: referenceCylinder,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
            guard section.count == 1,
                  case let .curve(curve) = section[0] else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Equal-radius cylinder bisector section did not produce one closed curve."
                )
            }
            return try verifier.curve(
                curve.curve,
                kind: .mixed,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
                tolerance: tolerance
            )
        }
    }

    private func closestApproach(
        firstOrigin: Point3D,
        firstAxis: Vector3D,
        secondOrigin: Point3D,
        secondAxis: Vector3D
    ) -> (firstPoint: Point3D, secondPoint: Point3D, distance: Double) {
        let originOffset = firstOrigin - secondOrigin
        let axisDot = firstAxis.dot(secondAxis)
        let denominator = 1.0 - axisDot * axisDot
        let firstParameter = (
            axisDot * originOffset.dot(secondAxis) - originOffset.dot(firstAxis)
        ) / denominator
        let secondParameter = axisDot * firstParameter + originOffset.dot(secondAxis)
        let firstPoint = firstOrigin + firstAxis * firstParameter
        let secondPoint = secondOrigin + secondAxis * secondParameter
        return (firstPoint, secondPoint, (firstPoint - secondPoint).length)
    }

    private func canonicalAxes(
        _ first: Vector3D,
        _ second: Vector3D
    ) -> (first: Vector3D, second: Vector3D) {
        let first = canonicalDirection(first)
        let second = canonicalDirection(second)
        if lexicographicallyPrecedes(first, second) {
            return (first, second)
        }
        return (second, first)
    }

    private func canonicalDirection(_ direction: Vector3D) -> Vector3D {
        if direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0 && direction.y == 0.0 && direction.z < 0.0) {
            return -direction
        }
        return direction
    }

    private func lexicographicallyPrecedes(_ lhs: Vector3D, _ rhs: Vector3D) -> Bool {
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.z < rhs.z
    }
}
