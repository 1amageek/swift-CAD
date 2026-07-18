import Foundation
import CADCore

struct BoundedPlaneConeSurfaceIntersector {
    private struct Hyperbola {
        let center: Point3D
        let transverseAxis: Vector3D
        let conjugateAxis: Vector3D
        let transverseRadius: Double
        let conjugateRadius: Double

        func point(parameter: Double, branch: Double) -> Point3D {
            center
                + transverseAxis * (branch * transverseRadius * cosh(parameter))
                + conjugateAxis * (conjugateRadius * sinh(parameter))
        }

        func coordinate(
            of point: Point3D,
            tolerance: ModelingTolerance
        ) throws -> (branch: Int, parameter: Double) {
            let offset = point - center
            let transverse = offset.dot(transverseAxis)
            let conjugate = offset.dot(conjugateAxis)
            let branch = transverse >= 0.0 ? 1 : -1
            let parameter = asinh(conjugate / conjugateRadius)
            let projected = self.point(parameter: parameter, branch: Double(branch))
            let residual = (point - projected).length
            guard parameter.isFinite, residual <= tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "Plane-cone boundary contact does not lie on the classified hyperbola."
                )
            }
            return (branch, parameter)
        }
    }

    private struct Parabola {
        let vertex: Point3D
        let tangentAxis: Vector3D
        let curvatureAxis: Vector3D
        let curvatureCoefficient: Double

        func point(parameter: Double) -> Point3D {
            vertex
                + tangentAxis * parameter
                + curvatureAxis * (curvatureCoefficient * parameter * parameter)
        }

        func parameter(
            of point: Point3D,
            tolerance: ModelingTolerance
        ) throws -> Double {
            let parameter = (point - vertex).dot(tangentAxis)
            let projected = self.point(parameter: parameter)
            let residual = (point - projected).length
            guard parameter.isFinite, residual <= tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "Plane-cone boundary contact does not lie on the classified parabola."
                )
            }
            return parameter
        }
    }

    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
        cone: CanonicalAnalyticSurface.Cone,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        boundaryPoints: [Point3D],
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection]? {
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
        let determinant = a00 * a11 - a01 * a01
        let coefficientScale = max(1.0, max(abs(a00), max(abs(a01), abs(a11))))
        let determinantTolerance = max(
            tolerance.angle * coefficientScale * coefficientScale,
            Double.ulpOfOne * 64.0
        )
        let containsApex = abs((cone.apex - plane.origin).dot(plane.normal))
            <= tolerance.distance
        guard containsApex == false else { return nil }
        guard boundaryPoints.count >= 2 else { return [] }
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
        if abs(determinant) <= determinantTolerance {
            return try parabolicIntersections(
                plane: plane,
                coneAxis: cone.axis,
                basisU: basis.u,
                basisV: basis.v,
                a00: a00,
                a01: a01,
                a11: a11,
                b0: b0,
                b1: b1,
                originOffset: originOffset,
                cosineSquared: cosineSquared,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                boundaryPoints: boundaryPoints,
                options: options,
                determinantTolerance: determinantTolerance,
                tolerance: tolerance
            )
        }
        guard determinant < -determinantTolerance else { return nil }

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
        let eigenDiscriminant = sqrt(
            max(0.0, pow(a00 - a11, 2.0) + 4.0 * a01 * a01)
        )
        let firstEigenvalue = (a00 + a11 + eigenDiscriminant) * 0.5
        let secondEigenvalue = (a00 + a11 - eigenDiscriminant) * 0.5
        guard abs(firstEigenvalue) > determinantTolerance,
              abs(secondEigenvalue) > determinantTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "Bounded plane-cone hyperbola has a singular principal frame."
            )
        }

        let firstAxis = try eigenvector(
            a00: a00,
            a01: a01,
            eigenvalue: firstEigenvalue,
            basisU: basis.u,
            basisV: basis.v,
            tolerance: tolerance
        )
        let secondAxis = try plane.normal.cross(firstAxis).normalized(
            tolerance: tolerance.distance
        )
        let firstRadiusSquared = -centerValue / firstEigenvalue
        let secondRadiusSquared = -centerValue / secondEigenvalue
        let hyperbola: Hyperbola
        if firstRadiusSquared > tolerance.distance * tolerance.distance,
           secondRadiusSquared < -tolerance.distance * tolerance.distance {
            hyperbola = Hyperbola(
                center: center,
                transverseAxis: firstAxis,
                conjugateAxis: secondAxis,
                transverseRadius: sqrt(firstRadiusSquared),
                conjugateRadius: sqrt(-secondRadiusSquared)
            )
        } else if secondRadiusSquared > tolerance.distance * tolerance.distance,
                  firstRadiusSquared < -tolerance.distance * tolerance.distance {
            hyperbola = Hyperbola(
                center: center,
                transverseAxis: secondAxis,
                conjugateAxis: firstAxis,
                transverseRadius: sqrt(secondRadiusSquared),
                conjugateRadius: sqrt(-firstRadiusSquared)
            )
        } else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "Bounded plane-cone section is not a regular hyperbola."
            )
        }

        var branchParameters: [Int: [Double]] = [:]
        for point in deduplicated(boundaryPoints, tolerance: tolerance) {
            let coordinate = try hyperbola.coordinate(of: point, tolerance: tolerance)
            branchParameters[coordinate.branch, default: []].append(coordinate.parameter)
        }
        let builder = SurfaceIntersectionSplineBuilder(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            options: options,
            tolerance: tolerance
        )
        var result: [SurfaceSurfaceIntersection] = []
        for branch in branchParameters.keys.sorted() {
            let parameters = deduplicated(
                branchParameters[branch] ?? [],
                tolerance: tolerance
            )
            guard let lower = parameters.first,
                  let upper = parameters.last,
                  upper - lower > tolerance.angle else {
                continue
            }
            let segmentCount = min(8, max(1, options.maximumSeedCount))
            let breaks = (0...segmentCount).map { index in
                lower + (upper - lower) * Double(index) / Double(segmentCount)
            }
            result.append(try builder.intersection(
                parameterRange: lower...upper,
                initialBreaks: breaks,
                kind: .transverse,
                isClosed: false,
                pointAt: { parameter in
                    hyperbola.point(parameter: parameter, branch: Double(branch))
                }
            ))
        }
        return result
    }

    private func parabolicIntersections(
        plane: CanonicalAnalyticSurface.Plane,
        coneAxis: Vector3D,
        basisU: Vector3D,
        basisV: Vector3D,
        a00: Double,
        a01: Double,
        a11: Double,
        b0: Double,
        b1: Double,
        originOffset: Vector3D,
        cosineSquared: Double,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        boundaryPoints: [Point3D],
        options: SurfaceSurfaceIntersectionOptions,
        determinantTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let eigenvalue = a00 + a11
        guard abs(eigenvalue) > determinantTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: abs(eigenvalue),
                tolerance: tolerance,
                message: "Bounded plane-cone parabola has a singular quadratic axis."
            )
        }
        let tangentAxis = try eigenvector(
            a00: a00,
            a01: a01,
            eigenvalue: eigenvalue,
            basisU: basisU,
            basisV: basisV,
            tolerance: tolerance
        )
        let curvatureAxis = try plane.normal.cross(tangentAxis).normalized(
            tolerance: tolerance.distance
        )
        let tangentLinear = b0 * tangentAxis.dot(basisU)
            + b1 * tangentAxis.dot(basisV)
        let curvatureLinear = b0 * curvatureAxis.dot(basisU)
            + b1 * curvatureAxis.dot(basisV)
        let linearScale = max(1.0, max(abs(b0), abs(b1)))
        guard abs(curvatureLinear) > tolerance.distance * linearScale else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: abs(curvatureLinear),
                tolerance: tolerance,
                message: "Bounded plane-cone parabolic section has a degenerate linear axis."
            )
        }
        let constant = quadraticForm(
            originOffset,
            originOffset,
            axis: coneAxis,
            cosineSquared: cosineSquared
        )
        let tangentOffset = -tangentLinear / eigenvalue
        let completedConstant = constant
            - tangentLinear * tangentLinear / eigenvalue
        let curvatureOffset = -completedConstant / (2.0 * curvatureLinear)
        let parabola = Parabola(
            vertex: plane.origin
                + tangentAxis * tangentOffset
                + curvatureAxis * curvatureOffset,
            tangentAxis: tangentAxis,
            curvatureAxis: curvatureAxis,
            curvatureCoefficient: -eigenvalue / (2.0 * curvatureLinear)
        )
        let parameters = try deduplicated(boundaryPoints, tolerance: tolerance).map {
            try parabola.parameter(of: $0, tolerance: tolerance)
        }
        let uniqueParameters = deduplicated(parameters, tolerance: tolerance)
        guard let lower = uniqueParameters.first,
              let upper = uniqueParameters.last,
              upper - lower > tolerance.angle else {
            return []
        }
        let segmentCount = min(8, max(1, options.maximumSeedCount))
        let breaks = (0...segmentCount).map { index in
            lower + (upper - lower) * Double(index) / Double(segmentCount)
        }
        let builder = SurfaceIntersectionSplineBuilder(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            options: options,
            tolerance: tolerance
        )
        return [try builder.intersection(
            parameterRange: lower...upper,
            initialBreaks: breaks,
            kind: .transverse,
            isClosed: false,
            pointAt: parabola.point
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

    private func deduplicated(
        _ points: [Point3D],
        tolerance: ModelingTolerance
    ) -> [Point3D] {
        points.sorted(by: lexicographicPointOrder).reduce(into: []) { result, point in
            if result.last.map({ ($0 - point).length <= tolerance.distance }) != true {
                result.append(point)
            }
        }
    }

    private func deduplicated(
        _ parameters: [Double],
        tolerance: ModelingTolerance
    ) -> [Double] {
        parameters.sorted().reduce(into: []) { result, parameter in
            if result.last.map({ abs($0 - parameter) <= tolerance.angle }) != true {
                result.append(parameter)
            }
        }
    }

    private func lexicographicPointOrder(_ lhs: Point3D, _ rhs: Point3D) -> Bool {
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.z < rhs.z
    }
}
