import Foundation
import CADCore

public struct DefaultCurveSurfaceIntersector: CurveSurfaceIntersecting {
    public init() {}

    public func intersections(
        curve: Curve3D,
        surface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        try options.validate(tolerance: tolerance)
        try curve.validate(tolerance: tolerance)
        try surface.validate(tolerance: tolerance)

        if let intersections = try closedFormEllipticPlanarIntersections(
            curve: curve,
            surface: surface,
            options: options,
            tolerance: tolerance
        ) {
            return intersections
        }

        if let intersections = try closedFormCircularPlanarIntersections(
            curve: curve,
            surface: surface,
            options: options,
            tolerance: tolerance
        ) {
            return intersections
        }

        if let line = lineGeometry(curve) {
            if let coefficients = try implicitPolynomial(
                line: line,
                surface: surface,
                tolerance: tolerance
            ) {
                return try closedFormLineIntersections(
                    line: line,
                    curve: curve,
                    surface: surface,
                    coefficients: coefficients,
                    options: options,
                    tolerance: tolerance
                )
            }
        }

        if let intersections = try closedFormHarmonicAnalyticIntersections(
            curve: curve,
            surface: surface,
            options: options,
            tolerance: tolerance
        ) {
            return intersections
        }

        return try adaptiveIntersections(
            curve: curve,
            surface: surface,
            options: options,
            tolerance: tolerance
        )
    }

    private func closedFormEllipticPlanarIntersections(
        curve: Curve3D,
        surface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection]? {
        guard case let .analytic(.ellipse(
            center,
            normal,
            majorAxis,
            majorRadius,
            minorRadius
        )) = curve,
              let plane = planarGeometry(surface) else {
            return nil
        }
        let minorAxis = try normal.cross(majorAxis).normalized(
            tolerance: tolerance.distance
        )
        let constant = (center - plane.origin).dot(plane.normal)
        let cosineCoefficient = majorAxis.dot(plane.normal) * majorRadius
        let sineCoefficient = minorAxis.dot(plane.normal) * minorRadius
        let amplitude = hypot(cosineCoefficient, sineCoefficient)
        if amplitude <= tolerance.distance {
            guard abs(constant) > tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .nonDiscreteIntersection,
                    residual: abs(constant),
                    tolerance: tolerance,
                    message: "Elliptic curve and plane are coincident; the intersection is not a discrete point set."
                )
            }
            return []
        }
        guard abs(constant) <= amplitude + tolerance.distance else {
            return []
        }

        let phase = atan2(sineCoefficient, cosineCoefficient)
        let normalizedConstant = min(max(-constant / amplitude, -1.0), 1.0)
        let angularOffset = acos(normalizedConstant)
        let first = normalizedPeriodicParameter(phase - angularOffset)
        let second = normalizedPeriodicParameter(phase + angularOffset)
        let parameters = abs(sin(angularOffset)) <= tolerance.angle
            ? [first]
            : [first, second]

        var intersections: [CurveSurfaceIntersection] = []
        for parameter in parameters {
            guard contains(parameter, range: options.curveRange),
                  try curve.parameterDomain.contains(parameter, tolerance: tolerance) else {
                continue
            }
            let curveGeometry = try curve.differentialGeometry(
                at: parameter,
                tolerance: tolerance
            )
            let surfaceProjection = try surface.parameterProjection(
                of: curveGeometry.position,
                tolerance: tolerance
            )
            guard contains(surfaceProjection.u, range: options.surfaceURange),
                  contains(surfaceProjection.v, range: options.surfaceVRange) else {
                continue
            }
            let planeResidual = abs(
                (curveGeometry.position - plane.origin).dot(plane.normal)
            )
            let residual = max(planeResidual, surfaceProjection.residual)
            guard residual <= tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "Closed-form ellipse-plane intersection failed residual verification."
                )
            }
            intersections.append(try CurveSurfaceIntersection(
                point: curveGeometry.position,
                curveParameter: parameter,
                surfaceU: surfaceProjection.u,
                surfaceV: surfaceProjection.v,
                kind: abs(curveGeometry.tangent.dot(plane.normal)) <= tolerance.angle
                    ? .tangent
                    : .transverse,
                residual: residual,
                iterations: 0
            ))
        }
        return deduplicated(intersections, tolerance: tolerance)
    }

    private func closedFormHarmonicAnalyticIntersections(
        curve: Curve3D,
        surface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection]? {
        guard let harmonic = try harmonicCurveGeometry(
            curve,
            tolerance: tolerance
        ),
        let coefficients = harmonicImplicitPolynomial(
            center: harmonic.center,
            cosine: harmonic.cosine,
            sine: harmonic.sine,
            surface: surface
        ) else {
            return nil
        }
        let coefficientScale = max(coefficients.map(abs).max() ?? 0.0, 1.0)
        if coefficients.allSatisfy({
            abs($0) <= coefficientScale * tolerance.angle
        }) {
            throw KernelError(
                phase: .geometry,
                code: .nonDiscreteIntersection,
                tolerance: tolerance,
                message: "Harmonic curve and analytic surface share a continuous intersection."
            )
        }
        let solver = try RealPolynomialRootSolver(
            rootTolerance: max(
                tolerance.angle * 0.001,
                Double.ulpOfOne * 64.0
            ),
            residualTolerance: max(
                tolerance.angle * 0.001,
                Double.ulpOfOne * 64.0
            )
        )
        var parameters = try solver.realRoots(coefficients: coefficients).compactMap {
            resolvedCurveParameter(
                normalizedPeriodicParameter(2.0 * atan($0)),
                domain: curve.parameterDomain,
                range: options.curveRange,
                tolerance: tolerance
            )
        }
        if let poleParameter = resolvedCurveParameter(
            Double.pi,
            domain: curve.parameterDomain,
            range: options.curveRange,
            tolerance: tolerance
        ) {
            let polePoint = try curve.point(
                at: poleParameter,
                tolerance: tolerance
            )
            do {
                _ = try surface.parameterProjection(
                    of: polePoint,
                    tolerance: tolerance
                )
                parameters.append(poleParameter)
            } catch let error as KernelError
                where error.code == .intersectionFailure {
                // The tan-half-angle pole is not an intersection.
            }
        }

        var intersections: [CurveSurfaceIntersection] = []
        for parameter in parameters {
            guard contains(parameter, range: options.curveRange) else {
                continue
            }
            let curveGeometry = try curve.differentialGeometry(
                at: parameter,
                tolerance: tolerance
            )
            let surfaceProjection = try surface.parameterProjection(
                of: curveGeometry.position,
                tolerance: tolerance
            )
            guard contains(surfaceProjection.u, range: options.surfaceURange),
                  contains(surfaceProjection.v, range: options.surfaceVRange) else {
                continue
            }
            let residual = surfaceProjection.residual
            guard residual <= tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "Closed-form harmonic curve-surface intersection failed residual verification."
                )
            }
            let surfaceNormal = try normal(
                at: curveGeometry.position,
                on: surface,
                u: surfaceProjection.u,
                v: surfaceProjection.v,
                tolerance: tolerance
            )
            intersections.append(try CurveSurfaceIntersection(
                point: curveGeometry.position,
                curveParameter: parameter,
                surfaceU: surfaceProjection.u,
                surfaceV: surfaceProjection.v,
                kind: abs(curveGeometry.tangent.dot(surfaceNormal)) <= tolerance.angle
                    ? .tangent
                    : .transverse,
                residual: residual,
                iterations: 0
            ))
        }
        return deduplicated(intersections, tolerance: tolerance)
    }

    private func harmonicCurveGeometry(
        _ curve: Curve3D,
        tolerance: ModelingTolerance
    ) throws -> (center: Point3D, cosine: Vector3D, sine: Vector3D)? {
        switch curve {
        case let .circle(circle):
            let normal = try circle.normal.normalized(
                tolerance: tolerance.distance
            )
            let helper = abs(normal.z) < 0.9
                ? Vector3D.unitZ
                : Vector3D.unitY
            let cosine = try helper.cross(normal).normalized(
                tolerance: tolerance.distance
            ) * circle.radius
            return (
                circle.center,
                cosine,
                normal.cross(cosine)
            )
        case let .analytic(analytic):
            switch analytic {
            case let .circle(center, normal, radius),
                 let .arc(center, normal, radius, _, _):
                let basis = try analyticOrthonormalBasis(
                    normal,
                    tolerance: tolerance
                )
                return (center, basis.u * radius, basis.v * radius)
            case let .ellipse(
                center,
                normal,
                majorAxis,
                majorRadius,
                minorRadius
            ):
                let minorAxis = try normal.cross(majorAxis).normalized(
                    tolerance: tolerance.distance
                )
                return (
                    center,
                    majorAxis * majorRadius,
                    minorAxis * minorRadius
                )
            case .line:
                return nil
            }
        case .line, .bSpline:
            return nil
        }
    }

    private func harmonicImplicitPolynomial(
        center: Point3D,
        cosine: Vector3D,
        sine: Vector3D,
        surface: Surface3D
    ) -> [Double]? {
        let denominator = [1.0, 0.0, 1.0]
        let denominatorSquared = multiplied(denominator, denominator)

        func relative(to origin: Point3D) -> [Vector3D] {
            [
                center + cosine - origin,
                sine * 2.0,
                center + (-cosine) - origin,
            ]
        }

        func cylinder(
            origin: Point3D,
            axis: Vector3D,
            radius: Double
        ) -> [Double] {
            let offset = relative(to: origin)
            let squaredDistance = vectorDot(offset, offset)
            let axial = offset.map { $0.dot(axis) }
            return subtracting(
                subtracting(squaredDistance, multiplied(axial, axial)),
                scaled(denominatorSquared, by: radius * radius)
            )
        }

        func cone(
            apex: Point3D,
            axis: Vector3D,
            halfAngle: Double
        ) -> [Double] {
            let offset = relative(to: apex)
            let squaredDistance = vectorDot(offset, offset)
            let axial = offset.map { $0.dot(axis) }
            return subtracting(
                squaredDistance,
                scaled(
                    multiplied(axial, axial),
                    by: 1.0 + pow(tan(halfAngle), 2.0)
                )
            )
        }

        func sphere(center: Point3D, radius: Double) -> [Double] {
            subtracting(
                vectorDot(relative(to: center), relative(to: center)),
                scaled(denominatorSquared, by: radius * radius)
            )
        }

        func torus(
            center: Point3D,
            axis: Vector3D,
            majorRadius: Double,
            minorRadius: Double
        ) -> [Double] {
            let offset = relative(to: center)
            let squaredDistance = vectorDot(offset, offset)
            let axial = offset.map { $0.dot(axis) }
            let radialSquared = subtracting(
                squaredDistance,
                multiplied(axial, axial)
            )
            let implicitQuadratic = adding(
                squaredDistance,
                scaled(
                    denominatorSquared,
                    by: majorRadius * majorRadius
                        - minorRadius * minorRadius
                )
            )
            return subtracting(
                multiplied(implicitQuadratic, implicitQuadratic),
                scaled(
                    multiplied(radialSquared, denominatorSquared),
                    by: 4.0 * majorRadius * majorRadius
                )
            )
        }

        switch surface {
        case let .plane(plane):
            return relative(to: plane.origin).map { $0.dot(plane.normal) }
        case let .cylinder(value):
            return cylinder(
                origin: value.origin,
                axis: value.axis,
                radius: value.radius
            )
        case let .analytic(analytic):
            switch analytic {
            case let .plane(origin, normal):
                return relative(to: origin).map { $0.dot(normal) }
            case let .cylinder(origin, axis, radius):
                return cylinder(origin: origin, axis: axis, radius: radius)
            case let .cone(apex, axis, halfAngle):
                return cone(apex: apex, axis: axis, halfAngle: halfAngle)
            case let .sphere(valueCenter, radius):
                return sphere(center: valueCenter, radius: radius)
            case let .torus(
                valueCenter,
                axis,
                majorRadius,
                minorRadius
            ):
                return torus(
                    center: valueCenter,
                    axis: axis,
                    majorRadius: majorRadius,
                    minorRadius: minorRadius
                )
            }
        case .bSpline:
            return nil
        }
    }

    private func vectorDot(
        _ lhs: [Vector3D],
        _ rhs: [Vector3D]
    ) -> [Double] {
        var result = Array(
            repeating: 0.0,
            count: lhs.count + rhs.count - 1
        )
        for lhsIndex in lhs.indices {
            for rhsIndex in rhs.indices {
                result[lhsIndex + rhsIndex] += lhs[lhsIndex].dot(rhs[rhsIndex])
            }
        }
        return result
    }

    private func multiplied(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        var result = Array(
            repeating: 0.0,
            count: lhs.count + rhs.count - 1
        )
        for lhsIndex in lhs.indices {
            for rhsIndex in rhs.indices {
                result[lhsIndex + rhsIndex] += lhs[lhsIndex] * rhs[rhsIndex]
            }
        }
        return result
    }

    private func adding(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        let count = max(lhs.count, rhs.count)
        return (0..<count).map { index in
            (index < lhs.count ? lhs[index] : 0.0)
                + (index < rhs.count ? rhs[index] : 0.0)
        }
    }

    private func subtracting(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        adding(lhs, scaled(rhs, by: -1.0))
    }

    private func scaled(_ polynomial: [Double], by scale: Double) -> [Double] {
        polynomial.map { $0 * scale }
    }

    private func resolvedCurveParameter(
        _ canonical: Double,
        domain: ParameterDomain,
        range: ScalarInterval?,
        tolerance: ModelingTolerance
    ) -> Double? {
        switch domain {
        case let .periodic(period):
            guard let range else { return canonical }
            let cycle = ceil((range.lower - canonical - tolerance.angle) / period)
            let candidate = canonical + cycle * period
            return candidate <= range.upper + tolerance.angle ? candidate : nil
        case let .closed(lower, upper):
            let effectiveLower = max(lower, range?.lower ?? lower)
            let effectiveUpper = min(upper, range?.upper ?? upper)
            guard effectiveLower <= effectiveUpper else { return nil }
            let period = 2.0 * Double.pi
            let cycle = ceil((effectiveLower - canonical - tolerance.angle) / period)
            let candidate = canonical + cycle * period
            return candidate <= effectiveUpper + tolerance.angle ? candidate : nil
        case .unbounded:
            return nil
        }
    }

    private func closedFormCircularPlanarIntersections(
        curve: Curve3D,
        surface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection]? {
        guard let circle = circularGeometry(curve),
              let plane = planarGeometry(surface) else {
            return nil
        }

        let normalCross = circle.normal.cross(plane.normal)
        let signedCenterDistance = (circle.center - plane.origin).dot(plane.normal)
        if normalCross.length <= tolerance.angle {
            guard abs(signedCenterDistance) > tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .nonDiscreteIntersection,
                    residual: abs(signedCenterDistance),
                    tolerance: tolerance,
                    message: "Circular curve and plane are coincident; the intersection is not a discrete point set."
                )
            }
            return []
        }

        let inCirclePlaneNormal = plane.normal - circle.normal * plane.normal.dot(circle.normal)
        let squaredLength = inCirclePlaneNormal.dot(inCirclePlaneNormal)
        guard squaredLength > tolerance.angle * tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Circle-plane intersection could not construct a stable in-plane normal."
            )
        }
        let lineAnchor = circle.center
            + inCirclePlaneNormal * (-signedCenterDistance / squaredLength)
        let centerToLineDistance = (lineAnchor - circle.center).length
        guard centerToLineDistance <= circle.radius + tolerance.distance else {
            return []
        }

        let lineDirection = try normalCross.normalized(tolerance: tolerance.angle)
        let halfChordSquared = max(
            0.0,
            circle.radius * circle.radius - centerToLineDistance * centerToLineDistance
        )
        let halfChord = sqrt(halfChordSquared)
        let candidates: [Point3D]
        if halfChord <= tolerance.distance {
            candidates = [lineAnchor]
        } else {
            candidates = [
                lineAnchor + lineDirection * -halfChord,
                lineAnchor + lineDirection * halfChord,
            ]
        }

        var intersections: [CurveSurfaceIntersection] = []
        for point in candidates {
            let curveProjection: CurveParameterProjection
            do {
                curveProjection = try curve.parameterProjection(
                    of: point,
                    tolerance: tolerance
                )
            } catch let error as KernelError where error.code == .intersectionFailure {
                continue
            }
            guard contains(curveProjection.parameter, range: options.curveRange) else {
                continue
            }
            let surfaceProjection = try surface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            guard contains(surfaceProjection.u, range: options.surfaceURange),
                  contains(surfaceProjection.v, range: options.surfaceVRange) else {
                continue
            }
            let curveGeometry = try curve.differentialGeometry(
                at: curveProjection.parameter,
                tolerance: tolerance
            )
            let residual = max(curveProjection.residual, surfaceProjection.residual)
            guard residual <= tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "Closed-form circle-plane intersection failed residual verification."
                )
            }
            intersections.append(try CurveSurfaceIntersection(
                point: point,
                curveParameter: curveProjection.parameter,
                surfaceU: surfaceProjection.u,
                surfaceV: surfaceProjection.v,
                kind: abs(curveGeometry.tangent.dot(plane.normal)) <= tolerance.angle
                    ? .tangent
                    : .transverse,
                residual: residual,
                iterations: 0
            ))
        }
        return deduplicated(intersections, tolerance: tolerance)
    }

    private func circularGeometry(
        _ curve: Curve3D
    ) -> (center: Point3D, normal: Vector3D, radius: Double)? {
        switch curve {
        case let .circle(circle):
            return (circle.center, circle.normal, circle.radius)
        case let .analytic(.circle(center, normal, radius)),
             let .analytic(.arc(center, normal, radius, _, _)):
            return (center, normal, radius)
        case .line, .analytic, .bSpline:
            return nil
        }
    }

    private func planarGeometry(
        _ surface: Surface3D
    ) -> (origin: Point3D, normal: Vector3D)? {
        switch surface {
        case let .plane(plane):
            return (plane.origin, plane.normal)
        case let .analytic(.plane(origin, normal)):
            return (origin, normal)
        case .cylinder, .analytic, .bSpline:
            return nil
        }
    }

    private func lineGeometry(_ curve: Curve3D) -> Line3D? {
        switch curve {
        case let .line(line):
            return line
        case let .analytic(.line(origin, direction)):
            return Line3D(origin: origin, direction: direction)
        case .circle, .analytic, .bSpline:
            return nil
        }
    }

    private func implicitPolynomial(
        line: Line3D,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [Double]? {
        switch surface {
        case let .plane(plane):
            return try planePolynomial(line: line, origin: plane.origin, normal: plane.normal, tolerance: tolerance)
        case let .cylinder(cylinder):
            return cylinderPolynomial(
                line: line,
                origin: cylinder.origin,
                axis: cylinder.axis,
                radius: cylinder.radius
            )
        case let .analytic(surface):
            switch surface {
            case let .plane(origin, normal):
                return try planePolynomial(line: line, origin: origin, normal: normal, tolerance: tolerance)
            case let .cylinder(origin, axis, radius):
                return cylinderPolynomial(line: line, origin: origin, axis: axis, radius: radius)
            case let .cone(apex, axis, halfAngle):
                return conePolynomial(line: line, apex: apex, axis: axis, halfAngle: halfAngle)
            case let .sphere(center, radius):
                let offset = line.origin - center
                return [
                    offset.dot(offset) - radius * radius,
                    2.0 * offset.dot(line.direction),
                    line.direction.dot(line.direction),
                ]
            case let .torus(center, axis, majorRadius, minorRadius):
                return torusPolynomial(
                    line: line,
                    center: center,
                    axis: axis,
                    majorRadius: majorRadius,
                    minorRadius: minorRadius
                )
            }
        case .bSpline:
            return nil
        }
    }

    private func planePolynomial(
        line: Line3D,
        origin: Point3D,
        normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let constant = (line.origin - origin).dot(normal)
        let linear = line.direction.dot(normal)
        if abs(constant) <= tolerance.distance,
           abs(linear) <= tolerance.angle {
            throw KernelError(
                phase: .geometry,
                code: .nonDiscreteIntersection,
                residual: abs(constant),
                tolerance: tolerance,
                message: "Curve and surface are coincident; the intersection is not a discrete point set."
            )
        }
        return [constant, linear]
    }

    private func cylinderPolynomial(
        line: Line3D,
        origin: Point3D,
        axis: Vector3D,
        radius: Double
    ) -> [Double] {
        let offset = line.origin - origin
        let axialPoint = offset.dot(axis)
        let axialDirection = line.direction.dot(axis)
        let radialPoint = offset - axis * axialPoint
        let radialDirection = line.direction - axis * axialDirection
        return [
            radialPoint.dot(radialPoint) - radius * radius,
            2.0 * radialPoint.dot(radialDirection),
            radialDirection.dot(radialDirection),
        ]
    }

    private func conePolynomial(
        line: Line3D,
        apex: Point3D,
        axis: Vector3D,
        halfAngle: Double
    ) -> [Double] {
        let offset = line.origin - apex
        let axialPoint = offset.dot(axis)
        let axialDirection = line.direction.dot(axis)
        let radialPoint = offset - axis * axialPoint
        let radialDirection = line.direction - axis * axialDirection
        let tangentSquared = pow(tan(halfAngle), 2.0)
        return [
            radialPoint.dot(radialPoint) - axialPoint * axialPoint * tangentSquared,
            2.0 * (radialPoint.dot(radialDirection) - axialPoint * axialDirection * tangentSquared),
            radialDirection.dot(radialDirection) - axialDirection * axialDirection * tangentSquared,
        ]
    }

    private func torusPolynomial(
        line: Line3D,
        center: Point3D,
        axis: Vector3D,
        majorRadius: Double,
        minorRadius: Double
    ) -> [Double] {
        let offset = line.origin - center
        let directionSquared = line.direction.dot(line.direction)
        let pointDirection = offset.dot(line.direction)
        let pointSquared = offset.dot(offset)
        let axialPoint = offset.dot(axis)
        let axialDirection = line.direction.dot(axis)
        let q0 = pointSquared + majorRadius * majorRadius - minorRadius * minorRadius
        let q1 = 2.0 * pointDirection
        let q2 = directionSquared
        let radial0 = pointSquared - axialPoint * axialPoint
        let radial1 = 2.0 * (pointDirection - axialPoint * axialDirection)
        let radial2 = directionSquared - axialDirection * axialDirection
        let majorFactor = 4.0 * majorRadius * majorRadius
        return [
            q0 * q0 - majorFactor * radial0,
            2.0 * q0 * q1 - majorFactor * radial1,
            q1 * q1 + 2.0 * q0 * q2 - majorFactor * radial2,
            2.0 * q1 * q2,
            q2 * q2,
        ]
    }

    private func closedFormLineIntersections(
        line: Line3D,
        curve: Curve3D,
        surface: Surface3D,
        coefficients: [Double],
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        let coefficientScale = max(coefficients.map(abs).max() ?? 0.0, 1.0)
        if coefficients.allSatisfy({ abs($0) <= coefficientScale * tolerance.angle }) {
            throw KernelError(
                phase: .geometry,
                code: .nonDiscreteIntersection,
                tolerance: tolerance,
                message: "Curve and surface share a continuous intersection; a discrete point set cannot represent it."
            )
        }
        let solver = try RealPolynomialRootSolver(
            rootTolerance: max(tolerance.distance * 0.001, Double.ulpOfOne * 64.0),
            residualTolerance: max(tolerance.angle * 0.001, Double.ulpOfOne * 64.0)
        )
        let roots = try solver.realRoots(coefficients: coefficients)
        var results: [CurveSurfaceIntersection] = []
        for parameter in roots {
            if let range = options.curveRange,
               range.contains(parameter) == false {
                continue
            }
            guard try curve.parameterDomain.contains(parameter, tolerance: tolerance) else {
                continue
            }
            let point = line.origin + line.direction * parameter
            let surfaceParameter = try surface.parameterProjection(of: point, tolerance: tolerance)
            guard contains(surfaceParameter.u, range: options.surfaceURange),
                  contains(surfaceParameter.v, range: options.surfaceVRange),
                  try surface.uDomain.contains(surfaceParameter.u, tolerance: tolerance),
                  try surface.vDomain.contains(surfaceParameter.v, tolerance: tolerance) else {
                continue
            }
            let surfacePoint = try surface.point(
                u: surfaceParameter.u,
                v: surfaceParameter.v,
                tolerance: tolerance
            )
            let residual = (point - surfacePoint).length
            guard residual <= tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "Closed-form curve-surface intersection failed residual verification."
                )
            }
            let normal = try normal(
                at: point,
                on: surface,
                u: surfaceParameter.u,
                v: surfaceParameter.v,
                tolerance: tolerance
            )
            let kind: CurveSurfaceIntersectionKind = abs(line.direction.dot(normal)) <= tolerance.angle
                ? .tangent
                : .transverse
            results.append(try CurveSurfaceIntersection(
                point: point,
                curveParameter: parameter,
                surfaceU: surfaceParameter.u,
                surfaceV: surfaceParameter.v,
                kind: kind,
                residual: residual,
                iterations: 0
            ))
        }
        return deduplicated(results, tolerance: tolerance)
    }

    private func adaptiveIntersections(
        curve: Curve3D,
        surface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        let curveRange = try resolvedInterval(
            domain: curve.parameterDomain,
            explicit: options.curveRange,
            label: "curve",
            tolerance: tolerance
        )
        let uRange = try resolvedInterval(
            domain: surface.uDomain,
            explicit: options.surfaceURange,
            label: "surface U",
            tolerance: tolerance
        )
        let vRange = try resolvedInterval(
            domain: surface.vDomain,
            explicit: options.surfaceVRange,
            label: "surface V",
            tolerance: tolerance
        )
        let rootCell = ParameterCell(t: curveRange, u: uRange, v: vRange, depth: 0)
        var pending = [rootCell]
        var seeds: [ParameterSeed] = []
        while let cell = pending.popLast() {
            let curveBounds = try bounds(curve: curve, interval: cell.t, tolerance: tolerance)
            let surfaceBounds = try bounds(
                surface: surface,
                uInterval: cell.u,
                vInterval: cell.v,
                tolerance: tolerance
            )
            guard curveBounds.intersects(surfaceBounds, tolerance: tolerance.distance) else {
                continue
            }
            if cell.depth >= options.maximumSubdivisionDepth {
                guard seeds.count < options.maximumSeedCount else {
                    throw KernelError(
                        phase: .geometry,
                        code: .resourceLimitExceeded,
                        tolerance: tolerance,
                        message: "Curve-surface adaptive subdivision exceeded its seed limit."
                    )
                }
                seeds.append(ParameterSeed(t: cell.t.midpoint, u: cell.u.midpoint, v: cell.v.midpoint))
                continue
            }
            let children = try subdivided(cell, root: rootCell)
            pending.append(contentsOf: children.reversed())
        }

        var intersections: [CurveSurfaceIntersection] = []
        for seed in seeds {
            if let intersection = try refinedIntersection(
                seed: seed,
                curve: curve,
                surface: surface,
                curveRange: curveRange,
                uRange: uRange,
                vRange: vRange,
                maximumIterations: options.maximumIterations,
                tolerance: tolerance
            ) {
                intersections.append(intersection)
            }
        }
        return deduplicated(intersections, tolerance: tolerance)
    }

    private func resolvedInterval(
        domain: ParameterDomain,
        explicit: ScalarInterval?,
        label: String,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        if let explicit {
            guard explicit.width > max(tolerance.angle, Double.ulpOfOne) else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "The explicit \(label) intersection range is degenerate."
                )
            }
            return explicit
        }
        switch domain {
        case let .closed(lower, upper):
            return try ScalarInterval(lower: lower, upper: upper)
        case let .periodic(period):
            return try ScalarInterval(lower: 0.0, upper: period)
        case .unbounded:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Adaptive intersection requires an explicit finite \(label) range."
            )
        }
    }

    private func bounds(
        curve: Curve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        if case let .bSpline(curve) = curve {
            return try BoundingBox3D(points: curve.controlPoints).expanded(by: tolerance.distance)
        }
        let derivativeBound: Double
        switch curve {
        case let .line(line):
            derivativeBound = line.direction.length
        case let .circle(circle):
            derivativeBound = circle.radius
        case let .analytic(curve):
            switch curve {
            case let .line(_, direction):
                derivativeBound = direction.length
            case let .circle(_, _, radius), let .arc(_, _, radius, _, _):
                derivativeBound = radius
            case let .ellipse(_, _, _, majorRadius, _):
                derivativeBound = majorRadius
            }
        case .bSpline:
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "B-spline curve interval bounds failed to use the control hull."
            )
        }
        let center = try curve.point(at: interval.midpoint, tolerance: tolerance)
        return try isotropicBounds(
            center: center,
            radius: derivativeBound * interval.width * 0.5 + tolerance.distance,
            tolerance: tolerance
        )
    }

    private func bounds(
        surface: Surface3D,
        uInterval: ScalarInterval,
        vInterval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        if case let .bSpline(surface) = surface {
            return try BoundingBox3D(points: surface.controlPoints.flatMap { $0 })
                .expanded(by: tolerance.distance)
        }
        let derivativeBounds: (u: Double, v: Double)
        switch surface {
        case .plane:
            derivativeBounds = (1.0, 1.0)
        case let .cylinder(cylinder):
            derivativeBounds = (cylinder.radius, 1.0)
        case let .analytic(surface):
            switch surface {
            case .plane:
                derivativeBounds = (1.0, 1.0)
            case let .cylinder(_, _, radius):
                derivativeBounds = (radius, 1.0)
            case let .cone(_, _, halfAngle):
                let maximumAbsoluteV = max(abs(vInterval.lower), abs(vInterval.upper))
                derivativeBounds = (maximumAbsoluteV * sin(halfAngle), 1.0)
            case let .sphere(_, radius):
                derivativeBounds = (radius, radius)
            case let .torus(_, _, majorRadius, minorRadius):
                derivativeBounds = (majorRadius + minorRadius, minorRadius)
            }
        case .bSpline:
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "B-spline surface interval bounds failed to use the control hull."
            )
        }
        let center = try surface.point(
            u: uInterval.midpoint,
            v: vInterval.midpoint,
            tolerance: tolerance
        )
        let radius = derivativeBounds.u * uInterval.width * 0.5
            + derivativeBounds.v * vInterval.width * 0.5
            + tolerance.distance
        return try isotropicBounds(center: center, radius: radius, tolerance: tolerance)
    }

    private func isotropicBounds(
        center: Point3D,
        radius: Double,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        guard radius.isFinite, radius >= 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: radius,
                tolerance: tolerance,
                message: "Curve-surface interval bounds produced an invalid radius."
            )
        }
        return try BoundingBox3D(
            minimum: Point3D(x: center.x - radius, y: center.y - radius, z: center.z - radius),
            maximum: Point3D(x: center.x + radius, y: center.y + radius, z: center.z + radius)
        )
    }

    private func subdivided(
        _ cell: ParameterCell,
        root: ParameterCell
    ) throws -> [ParameterCell] {
        let tScale = cell.t.width / root.t.width
        let uScale = cell.u.width / root.u.width
        let vScale = cell.v.width / root.v.width
        if tScale >= uScale, tScale >= vScale {
            let midpoint = cell.t.midpoint
            return [
                ParameterCell(
                    t: try ScalarInterval(lower: cell.t.lower, upper: midpoint),
                    u: cell.u,
                    v: cell.v,
                    depth: cell.depth + 1
                ),
                ParameterCell(
                    t: try ScalarInterval(lower: midpoint, upper: cell.t.upper),
                    u: cell.u,
                    v: cell.v,
                    depth: cell.depth + 1
                ),
            ]
        }
        if uScale >= vScale {
            let midpoint = cell.u.midpoint
            return [
                ParameterCell(
                    t: cell.t,
                    u: try ScalarInterval(lower: cell.u.lower, upper: midpoint),
                    v: cell.v,
                    depth: cell.depth + 1
                ),
                ParameterCell(
                    t: cell.t,
                    u: try ScalarInterval(lower: midpoint, upper: cell.u.upper),
                    v: cell.v,
                    depth: cell.depth + 1
                ),
            ]
        }
        let midpoint = cell.v.midpoint
        return [
            ParameterCell(
                t: cell.t,
                u: cell.u,
                v: try ScalarInterval(lower: cell.v.lower, upper: midpoint),
                depth: cell.depth + 1
            ),
            ParameterCell(
                t: cell.t,
                u: cell.u,
                v: try ScalarInterval(lower: midpoint, upper: cell.v.upper),
                depth: cell.depth + 1
            ),
        ]
    }

    private func refinedIntersection(
        seed: ParameterSeed,
        curve: Curve3D,
        surface: Surface3D,
        curveRange: ScalarInterval,
        uRange: ScalarInterval,
        vRange: ScalarInterval,
        maximumIterations: Int,
        tolerance: ModelingTolerance
    ) throws -> CurveSurfaceIntersection? {
        var current = seed
        for iteration in 0...maximumIterations {
            let curveGeometry = try curve.differentialGeometry(at: current.t, tolerance: tolerance)
            let surfaceGeometry = try surface.differentialGeometry(
                atU: current.u,
                v: current.v,
                tolerance: tolerance
            )
            let residualVector = curveGeometry.position - surfaceGeometry.position
            let residual = residualVector.length
            if residual <= tolerance.distance {
                let kind: CurveSurfaceIntersectionKind = abs(
                    curveGeometry.tangent.dot(surfaceGeometry.normal)
                ) <= tolerance.angle ? .tangent : .transverse
                return try CurveSurfaceIntersection(
                    point: curveGeometry.position,
                    curveParameter: current.t,
                    surfaceU: current.u,
                    surfaceV: current.v,
                    kind: kind,
                    residual: residual,
                    iterations: iteration
                )
            }
            guard iteration < maximumIterations else {
                return nil
            }
            let columnT = curveGeometry.firstDerivative
            let columnU = -surfaceGeometry.tangentU
            let columnV = -surfaceGeometry.tangentV
            let jacobianDeterminant = determinant(columnT, columnU, columnV)
            guard abs(jacobianDeterminant) > max(Double.ulpOfOne, tolerance.angle * tolerance.angle) else {
                return nil
            }
            let rightHandSide = -residualVector
            let delta = ParameterSeed(
                t: determinant(rightHandSide, columnU, columnV) / jacobianDeterminant,
                u: determinant(columnT, rightHandSide, columnV) / jacobianDeterminant,
                v: determinant(columnT, columnU, rightHandSide) / jacobianDeterminant
            )
            guard delta.t.isFinite, delta.u.isFinite, delta.v.isFinite else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "Curve-surface Newton refinement produced a non-finite step."
                )
            }
            var stepScale = 1.0
            var accepted: ParameterSeed?
            while stepScale >= 1.0 / 128.0 {
                let candidate = ParameterSeed(
                    t: clamped(current.t + delta.t * stepScale, to: curveRange),
                    u: clamped(current.u + delta.u * stepScale, to: uRange),
                    v: clamped(current.v + delta.v * stepScale, to: vRange)
                )
                let curvePoint = try curve.point(at: candidate.t, tolerance: tolerance)
                let surfacePoint = try surface.point(
                    u: candidate.u,
                    v: candidate.v,
                    tolerance: tolerance
                )
                if (curvePoint - surfacePoint).length < residual {
                    accepted = candidate
                    break
                }
                stepScale *= 0.5
            }
            guard let accepted else {
                return nil
            }
            current = accepted
        }
        return nil
    }

    private func normal(
        at point: Point3D,
        on surface: Surface3D,
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        switch surface {
        case let .plane(plane):
            return try plane.normal.normalized(tolerance: tolerance.distance)
        case let .cylinder(cylinder):
            let offset = point - cylinder.origin
            return try (offset - cylinder.axis * offset.dot(cylinder.axis))
                .normalized(tolerance: tolerance.distance)
        case let .analytic(surface):
            switch surface {
            case let .plane(_, normal):
                return normal
            case let .cylinder(origin, axis, _):
                let offset = point - origin
                return try (offset - axis * offset.dot(axis)).normalized(tolerance: tolerance.distance)
            case let .cone(apex, axis, halfAngle):
                let offset = point - apex
                let axialDistance = offset.dot(axis)
                let radial = try (offset - axis * axialDistance).normalized(tolerance: tolerance.distance)
                let sign = axialDistance >= 0.0 ? 1.0 : -1.0
                return try (radial * cos(halfAngle) - axis * (sign * sin(halfAngle)))
                    .normalized(tolerance: tolerance.distance)
            case let .sphere(center, _):
                return try (point - center).normalized(tolerance: tolerance.distance)
            case let .torus(center, axis, majorRadius, _):
                let offset = point - center
                let radial = offset - axis * offset.dot(axis)
                let radialDirection = try radial.normalized(tolerance: tolerance.distance)
                return try (point - (center + radialDirection * majorRadius))
                    .normalized(tolerance: tolerance.distance)
            }
        case .bSpline:
            return try surface.normal(u: u, v: v, tolerance: tolerance)
        }
    }

    private func contains(_ value: Double, range: ScalarInterval?) -> Bool {
        range?.contains(value) ?? true
    }

    private func normalizedPeriodicParameter(_ parameter: Double) -> Double {
        let period = 2.0 * Double.pi
        let remainder = parameter.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }

    private func determinant(_ first: Vector3D, _ second: Vector3D, _ third: Vector3D) -> Double {
        first.dot(second.cross(third))
    }

    private func clamped(_ value: Double, to interval: ScalarInterval) -> Double {
        min(max(value, interval.lower), interval.upper)
    }

    private func deduplicated(
        _ intersections: [CurveSurfaceIntersection],
        tolerance: ModelingTolerance
    ) -> [CurveSurfaceIntersection] {
        let sorted = intersections.sorted { lhs, rhs in
            if lhs.curveParameter != rhs.curveParameter {
                return lhs.curveParameter < rhs.curveParameter
            }
            if lhs.surfaceU != rhs.surfaceU {
                return lhs.surfaceU < rhs.surfaceU
            }
            return lhs.surfaceV < rhs.surfaceV
        }
        var result: [CurveSurfaceIntersection] = []
        for intersection in sorted {
            if let index = result.firstIndex(where: { existing in
                (existing.point - intersection.point).length <= tolerance.distance &&
                    abs(existing.curveParameter - intersection.curveParameter) <= max(tolerance.distance, tolerance.angle)
            }) {
                if intersection.residual < result[index].residual {
                    result[index] = intersection
                }
            } else {
                result.append(intersection)
            }
        }
        return result
    }

    private struct ParameterCell: Sendable {
        let t: ScalarInterval
        let u: ScalarInterval
        let v: ScalarInterval
        let depth: Int
    }

    private struct ParameterSeed: Sendable {
        let t: Double
        let u: Double
        let v: Double
    }
}
