import CADCore
import Foundation

struct BSplineCurveAnalyticSurfaceIntersector {
    func intersections(
        curve: BSplineCurve3D,
        surface: Surface3D,
        canonicalSurface: CanonicalAnalyticSurface,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        try curve.validate(tolerance: tolerance)
        try surface.validate(tolerance: tolerance)
        let curveParameterTolerance = parameterTolerance(
            for: curve.domain,
            tolerance: tolerance
        )
        let polynomialDegree = try implicitPolynomialDegree(
            curveDegree: curve.degree,
            surface: canonicalSurface
        )
        guard polynomialDegree <= options.maximumPolynomialDegree else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: Double(polynomialDegree),
                tolerance: tolerance,
                message: "The implicit intersection polynomial exceeds the requested degree budget."
            )
        }
        let spans = try BSplineCurveBezierDecomposer().curvePatches(
            curve: curve,
            tolerance: tolerance
        )
        var intersections: [CurveSurfaceIntersection] = []
        for span in spans {
            guard overlaps(
                lower: span.lower,
                upper: span.upper,
                range: options.curveRange,
                tolerance: curveParameterTolerance
            ) else {
                continue
            }
            let implicit = try implicitPolynomial(
                span: span,
                surface: canonicalSurface
            )
            let coefficientMagnitude = implicit.coefficients.map(abs).max() ?? 0.0
            let coincidenceTolerance = implicit.referenceScale * max(
                tolerance.relative,
                Double.ulpOfOne * 512.0
            )
            if coefficientMagnitude <= coincidenceTolerance {
                throw KernelError(
                    phase: .geometry,
                    code: .nonDiscreteIntersection,
                    tolerance: tolerance,
                    message: "A rational B-spline curve span is coincident with the analytic surface."
                )
            }
            let localRootTolerance = max(
                curveParameterTolerance / max(
                    span.upper - span.lower,
                    curveParameterTolerance
                ),
                Double.ulpOfOne * 64.0
            )
            let solver = try RealPolynomialRootSolver(
                rootTolerance: localRootTolerance,
                residualTolerance: max(
                    tolerance.relative * tolerance.relative,
                    Double.ulpOfOne * 64.0
                )
            )
            for localRoot in try solver.realRoots(
                coefficients: implicit.coefficients
            ) {
                guard localRoot >= -localRootTolerance,
                      localRoot <= 1.0 + localRootTolerance else {
                    continue
                }
                let refinement = refinedLocalRoot(
                    localRoot,
                    coefficients: implicit.coefficients,
                    maximumIterations: options.maximumIterations
                )
                let boundedRoot = min(max(refinement.value, 0.0), 1.0)
                let parameter = span.lower
                    + (span.upper - span.lower) * boundedRoot
                guard contains(
                    parameter,
                    range: options.curveRange,
                    tolerance: curveParameterTolerance
                ) else {
                    continue
                }
                let geometry = try curve.differentialGeometry(
                    at: parameter,
                    tolerance: tolerance
                )
                let projection = try surface.parameterProjection(
                    of: geometry.position,
                    tolerance: tolerance
                )
                guard let surfaceU = resolvedSurfaceParameter(
                    projection.u,
                    domain: surface.uDomain,
                    range: options.surfaceURange,
                    tolerance: tolerance
                ),
                let surfaceV = resolvedSurfaceParameter(
                    projection.v,
                    domain: surface.vDomain,
                    range: options.surfaceVRange,
                    tolerance: tolerance
                ) else {
                    continue
                }
                let residual = projection.residual
                guard residual <= tolerance.distance else {
                    throw KernelError(
                        phase: .geometry,
                        code: .intersectionFailure,
                        residual: residual,
                        tolerance: tolerance,
                        message: "Rational B-spline curve-analytic-surface root failed residual verification."
                    )
                }
                let surfaceNormal = try implicitNormal(
                    at: geometry.position,
                    surface: canonicalSurface,
                    tolerance: tolerance
                )
                intersections.append(try CurveSurfaceIntersection(
                    point: geometry.position,
                    curveParameter: parameter,
                    surfaceU: surfaceU,
                    surfaceV: surfaceV,
                    kind: abs(geometry.tangent.dot(surfaceNormal)) <= tolerance.angle
                        ? .tangent
                        : .transverse,
                    residual: residual,
                    iterations: refinement.iterations
                ))
            }
        }
        return deduplicated(
            intersections,
            curveParameterTolerance: curveParameterTolerance,
            tolerance: tolerance
        )
    }

    private func implicitPolynomial(
        span: RationalBezierCurvePatch3D,
        surface: CanonicalAnalyticSurface
    ) throws -> ImplicitPolynomial {
        let curve = try homogeneousCurve(span)
        let weightSquared = multiplied(curve.weight, curve.weight)
        let coefficients: [Double]
        let referenceTerms: [[Double]]
        switch surface {
        case let .plane(plane):
            let relative = relativeCurve(curve, to: plane.origin)
            coefficients = dot(relative, plane.normal)
            referenceTerms = [coefficients, curve.weight]
        case let .cylinder(cylinder):
            let relative = relativeCurve(curve, to: cylinder.origin)
            let axial = dot(relative, cylinder.axis)
            let radial = subtracting(
                relative,
                polynomialVector(direction: cylinder.axis, scale: axial)
            )
            let radialSquared = dot(radial, radial)
            let radiusSquared = scaled(
                weightSquared,
                by: cylinder.radius * cylinder.radius
            )
            coefficients = subtracting(radialSquared, radiusSquared)
            referenceTerms = [radialSquared, radiusSquared]
        case let .cone(cone):
            let relative = relativeCurve(curve, to: cone.apex)
            let axial = dot(relative, cone.axis)
            let radial = subtracting(
                relative,
                polynomialVector(direction: cone.axis, scale: axial)
            )
            let axialSquared = multiplied(axial, axial)
            let radialSquared = dot(radial, radial)
            let coneSquared = scaled(
                axialSquared,
                by: pow(tan(cone.halfAngle), 2.0)
            )
            coefficients = subtracting(radialSquared, coneSquared)
            referenceTerms = [radialSquared, coneSquared]
        case let .sphere(sphere):
            let relative = relativeCurve(curve, to: sphere.center)
            let squaredDistance = dot(relative, relative)
            let radiusSquared = scaled(
                weightSquared,
                by: sphere.radius * sphere.radius
            )
            coefficients = subtracting(squaredDistance, radiusSquared)
            referenceTerms = [squaredDistance, radiusSquared]
        case let .torus(torus):
            let relative = relativeCurve(curve, to: torus.center)
            let axial = dot(relative, torus.axis)
            let axialSquared = multiplied(axial, axial)
            let radial = subtracting(
                relative,
                polynomialVector(direction: torus.axis, scale: axial)
            )
            let radialSquared = dot(radial, radial)
            let squaredDistance = adding(radialSquared, axialSquared)
            let implicitQuadratic = adding(
                squaredDistance,
                scaled(
                    weightSquared,
                    by: torus.majorRadius * torus.majorRadius
                        - torus.minorRadius * torus.minorRadius
                )
            )
            let firstTerm = multiplied(
                implicitQuadratic,
                implicitQuadratic
            )
            let secondTerm = scaled(
                multiplied(radialSquared, weightSquared),
                by: 4.0 * torus.majorRadius * torus.majorRadius
            )
            coefficients = subtracting(firstTerm, secondTerm)
            referenceTerms = [firstTerm, secondTerm]
        case .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: nil,
                message: "The B-spline curve analytic intersector received a non-analytic surface."
            )
        }
        guard coefficients.isEmpty == false,
              coefficients.allSatisfy(\.isFinite) else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: nil,
                message: "B-spline implicit polynomial exceeded finite arithmetic."
            )
        }
        return ImplicitPolynomial(
            coefficients: coefficients,
            referenceScale: max(
                referenceTerms.flatMap { $0 }.map(abs).max() ?? 0.0,
                1.0
            )
        )
    }

    private func homogeneousCurve(
        _ span: RationalBezierCurvePatch3D
    ) throws -> HomogeneousCurve {
        try HomogeneousCurve(
            x: bernsteinToPower(span.controlPoints.indices.map {
                span.controlPoints[$0].x * span.weights[$0]
            }),
            y: bernsteinToPower(span.controlPoints.indices.map {
                span.controlPoints[$0].y * span.weights[$0]
            }),
            z: bernsteinToPower(span.controlPoints.indices.map {
                span.controlPoints[$0].z * span.weights[$0]
            }),
            weight: bernsteinToPower(span.weights)
        )
    }

    private func relativeCurve(
        _ curve: HomogeneousCurve,
        to origin: Point3D
    ) -> PolynomialVector3 {
        PolynomialVector3(
            x: subtracting(curve.x, scaled(curve.weight, by: origin.x)),
            y: subtracting(curve.y, scaled(curve.weight, by: origin.y)),
            z: subtracting(curve.z, scaled(curve.weight, by: origin.z))
        )
    }

    private func dot(
        _ lhs: PolynomialVector3,
        _ rhs: PolynomialVector3
    ) -> [Double] {
        adding(
            adding(
                multiplied(lhs.x, rhs.x),
                multiplied(lhs.y, rhs.y)
            ),
            multiplied(lhs.z, rhs.z)
        )
    }

    private func dot(
        _ value: PolynomialVector3,
        _ direction: Vector3D
    ) -> [Double] {
        adding(
            adding(
                scaled(value.x, by: direction.x),
                scaled(value.y, by: direction.y)
            ),
            scaled(value.z, by: direction.z)
        )
    }

    private func polynomialVector(
        direction: Vector3D,
        scale: [Double]
    ) -> PolynomialVector3 {
        PolynomialVector3(
            x: scaled(scale, by: direction.x),
            y: scaled(scale, by: direction.y),
            z: scaled(scale, by: direction.z)
        )
    }

    private func subtracting(
        _ lhs: PolynomialVector3,
        _ rhs: PolynomialVector3
    ) -> PolynomialVector3 {
        PolynomialVector3(
            x: subtracting(lhs.x, rhs.x),
            y: subtracting(lhs.y, rhs.y),
            z: subtracting(lhs.z, rhs.z)
        )
    }

    private func implicitNormal(
        at point: Point3D,
        surface: CanonicalAnalyticSurface,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        let gradient: Vector3D
        switch surface {
        case let .plane(plane):
            gradient = plane.normal
        case let .cylinder(cylinder):
            let relative = point - cylinder.origin
            let axial = relative.dot(cylinder.axis)
            gradient = relative - cylinder.axis * axial
        case let .cone(cone):
            let relative = point - cone.apex
            let axial = relative.dot(cone.axis)
            let radial = relative - cone.axis * axial
            gradient = radial - cone.axis * (
                axial * pow(tan(cone.halfAngle), 2.0)
            )
        case let .sphere(sphere):
            gradient = point - sphere.center
        case let .torus(torus):
            let relative = point - torus.center
            let axial = relative.dot(torus.axis)
            let radial = relative - torus.axis * axial
            let implicitQuadratic = relative.dot(relative)
                + torus.majorRadius * torus.majorRadius
                - torus.minorRadius * torus.minorRadius
            gradient = relative * implicitQuadratic
                - radial * (2.0 * torus.majorRadius * torus.majorRadius)
        case .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "An implicit normal requires an analytic surface."
            )
        }
        guard gradient.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: gradient.length,
                tolerance: tolerance,
                message: "The analytic surface gradient is singular at the curve intersection."
            )
        }
        return try gradient.normalized(tolerance: tolerance.distance)
    }

    private func implicitPolynomialDegree(
        curveDegree: Int,
        surface: CanonicalAnalyticSurface
    ) throws -> Int {
        let multiplier: Int
        switch surface {
        case .plane:
            multiplier = 1
        case .cylinder, .cone, .sphere:
            multiplier = 2
        case .torus:
            multiplier = 4
        case .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: nil,
                message: "An implicit polynomial requires an analytic surface."
            )
        }
        let result = curveDegree.multipliedReportingOverflow(by: multiplier)
        guard result.overflow == false else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: nil,
                message: "The implicit intersection polynomial degree overflowed."
            )
        }
        return result.partialValue
    }

    private func multiplied(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        var result = Array(repeating: 0.0, count: lhs.count + rhs.count - 1)
        for lhsIndex in lhs.indices {
            for rhsIndex in rhs.indices {
                result[lhsIndex + rhsIndex] += lhs[lhsIndex] * rhs[rhsIndex]
            }
        }
        return result
    }

    private func adding(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        let count = max(lhs.count, rhs.count)
        return (0..<count).map {
            ($0 < lhs.count ? lhs[$0] : 0.0)
                + ($0 < rhs.count ? rhs[$0] : 0.0)
        }
    }

    private func subtracting(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        adding(lhs, scaled(rhs, by: -1.0))
    }

    private func scaled(_ polynomial: [Double], by scale: Double) -> [Double] {
        polynomial.map { $0 * scale }
    }

    private func refinedLocalRoot(
        _ initial: Double,
        coefficients: [Double],
        maximumIterations: Int
    ) -> RefinedRoot {
        let derivative = coefficients.indices.dropFirst().map { index in
            coefficients[index] * Double(index)
        }
        let coefficientScale = max(coefficients.map(abs).max() ?? 0.0, 1.0)
        let arithmeticTolerance = coefficientScale * Double.ulpOfOne * 256.0
        var value = min(max(initial, 0.0), 1.0)
        var iterationCount = 0
        for iteration in 0..<maximumIterations {
            let residual = evaluate(coefficients, at: value)
            guard abs(residual) > arithmeticTolerance else { break }
            let slope = evaluate(derivative, at: value)
            guard abs(slope) > arithmeticTolerance else { break }
            let candidate = value - residual / slope
            guard candidate.isFinite else { break }
            let boundedCandidate = min(max(candidate, 0.0), 1.0)
            iterationCount = iteration + 1
            if boundedCandidate == value { break }
            value = boundedCandidate
        }
        return RefinedRoot(value: value, iterations: iterationCount)
    }

    private func evaluate(_ coefficients: [Double], at value: Double) -> Double {
        coefficients.reversed().reduce(0.0) { partial, coefficient in
            partial * value + coefficient
        }
    }

    private func parameterTolerance(
        for domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) -> Double {
        let machineFloor = Double.ulpOfOne * 128.0
        switch domain {
        case .unbounded:
            return max(tolerance.distance, machineFloor)
        case let .closed(lower, upper):
            let scale = max(abs(lower), max(abs(upper), upper - lower))
            return max(
                tolerance.angle,
                max(tolerance.relative * max(scale, 1.0), machineFloor)
            )
        case let .periodic(period):
            return max(
                tolerance.angle,
                max(tolerance.relative * period, machineFloor)
            )
        }
    }

    private func contains(
        _ value: Double,
        range: ScalarInterval?,
        tolerance: Double
    ) -> Bool {
        guard let range else { return true }
        return value >= range.lower - tolerance
            && value <= range.upper + tolerance
    }

    private func overlaps(
        lower: Double,
        upper: Double,
        range: ScalarInterval?,
        tolerance: Double
    ) -> Bool {
        guard let range else { return true }
        return lower <= range.upper + tolerance
            && range.lower <= upper + tolerance
    }

    private func resolvedSurfaceParameter(
        _ value: Double,
        domain: ParameterDomain,
        range: ScalarInterval?,
        tolerance: ModelingTolerance
    ) -> Double? {
        guard value.isFinite else { return nil }
        guard let range else { return value }
        let boundaryTolerance = parameterTolerance(
            for: domain,
            tolerance: tolerance
        )
        switch domain {
        case let .periodic(period):
            let lowerIndex = ceil(
                (range.lower - boundaryTolerance - value) / period
            )
            let upperIndex = floor(
                (range.upper + boundaryTolerance - value) / period
            )
            guard lowerIndex.isFinite,
                  upperIndex.isFinite,
                  lowerIndex <= upperIndex else {
                return nil
            }
            let preferredIndex = ((range.midpoint - value) / period).rounded()
            let selectedIndex = min(
                max(preferredIndex, lowerIndex),
                upperIndex
            )
            let resolved = value + selectedIndex * period
            return resolved.isFinite ? resolved : nil
        case .closed, .unbounded:
            return contains(
                value,
                range: range,
                tolerance: boundaryTolerance
            ) ? value : nil
        }
    }

    private func bernsteinToPower(_ coefficients: [Double]) throws -> [Double] {
        guard coefficients.isEmpty == false,
              coefficients.allSatisfy(\.isFinite) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "Bernstein coefficients must be finite and non-empty."
            )
        }
        let degree = coefficients.count - 1
        var result = Array(repeating: 0.0, count: coefficients.count)
        for power in 0...degree {
            let outer = try binomialCoefficient(degree, power)
            var sum = 0.0
            for index in 0...power {
                let inner = try binomialCoefficient(power, index)
                let sign = (power - index).isMultiple(of: 2) ? 1.0 : -1.0
                sum += sign * inner * coefficients[index]
            }
            result[power] = outer * sum
            guard result[power].isFinite else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: nil,
                    message: "Bernstein power conversion exceeded finite arithmetic."
                )
            }
        }
        return result
    }

    private func binomialCoefficient(_ n: Int, _ k: Int) throws -> Double {
        let count = min(k, n - k)
        guard count > 0 else {
            return 1.0
        }
        var result = 1.0
        for index in 1...count {
            result *= Double(n - count + index) / Double(index)
            guard result.isFinite else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: nil,
                    message: "B-spline degree exceeds finite polynomial conversion capacity."
                )
            }
        }
        return result
    }

    private func deduplicated(
        _ intersections: [CurveSurfaceIntersection],
        curveParameterTolerance: Double,
        tolerance: ModelingTolerance
    ) -> [CurveSurfaceIntersection] {
        let sorted = intersections.sorted {
            $0.curveParameter < $1.curveParameter
        }
        var result: [CurveSurfaceIntersection] = []
        for intersection in sorted {
            if let index = result.firstIndex(where: {
                abs($0.curveParameter - intersection.curveParameter)
                    <= curveParameterTolerance
                    && ($0.point - intersection.point).length <= tolerance.distance
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

    private struct HomogeneousCurve {
        let x: [Double]
        let y: [Double]
        let z: [Double]
        let weight: [Double]
    }

    private struct PolynomialVector3 {
        let x: [Double]
        let y: [Double]
        let z: [Double]
    }

    private struct ImplicitPolynomial {
        let coefficients: [Double]
        let referenceScale: Double
    }

    private struct RefinedRoot {
        let value: Double
        let iterations: Int
    }
}
