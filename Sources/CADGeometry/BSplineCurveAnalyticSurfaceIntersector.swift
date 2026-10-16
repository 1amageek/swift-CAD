import CADCore
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

struct BSplineCurveAnalyticSurfaceIntersector {
    func intersections(
        curve: BSplineCurve3D,
        surface: Surface3D,
        canonicalSurface: CanonicalAnalyticSurface,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [CurveSurfaceIntersection] {
        try execution.consumeWork(1)
        try curve.validate(tolerance: tolerance, using: &execution)
        try surface.validate(tolerance: tolerance, using: &execution)
        let curveParameterTolerance = try parameterTolerance(
            for: curve.domain,
            tolerance: tolerance, using: &execution
        )
        let polynomialDegree = try implicitPolynomialDegree(
            curveDegree: curve.degree,
            surface: canonicalSurface, using: &execution
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
            tolerance: tolerance, using: &execution
        )
        var intersections: [CurveSurfaceIntersection] = []
        for span in spans {
            try execution.consumeWork(1)
            guard try overlaps(
                lower: span.lower,
                upper: span.upper,
                range: options.curveRange,
                tolerance: curveParameterTolerance, using: &execution
            ) else {
                continue
            }
            let implicit = try implicitPolynomial(
                span: span,
                surface: canonicalSurface, using: &execution
            )
            var coefficientMagnitude = 0.0
            for coefficient in implicit.coefficients {
                try execution.consumeWork(1)
                coefficientMagnitude = max(coefficientMagnitude, abs(coefficient))
            }
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
            var rootCoefficients = implicit.coefficients
            var endpointRoots: [Double] = []
            if case .plane(let plane) = canonicalSurface {
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: span.controlPoints.count, of: Double.self))
                let coefficients = try span.controlPoints.indices.map {
                    try execution.consumeWork(1)
                    return (span.controlPoints[$0] - plane.origin).dot(plane.normal) * span.weights[$0]
                }
                if let first = coefficients.firstIndex(where: { $0 != 0 }),
                   let last = coefficients.lastIndex(where: { $0 != 0 }) {
                    // Remove exact endpoint factors in Bernstein form before
                    // power conversion can split a multiple endpoint root.
                    let degree = coefficients.count - 1
                    let reducedDegree = last - first
                    try execution.retainStorage(bytes: exactScalarPayloadBytes(count: reducedDegree + 1, of: Double.self))
                    var reduced: [Double] = []
                    reduced.reserveCapacity(reducedDegree + 1)
                    for index in first...last {
                        reduced.append(try coefficients[index]
                            * binomialCoefficient(degree, index, using: &execution)
                            / binomialCoefficient(reducedDegree, index - first, using: &execution))
                    }
                    rootCoefficients = try bernsteinToPower(reduced, using: &execution)
                    if first > 0 {
                        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
                        endpointRoots.append(0)
                    }
                    if last < degree {
                        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
                        endpointRoots.append(1)
                    }
                }
            }
            let roots = try solver.realRoots(coefficients: rootCoefficients, using: &execution)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: try checkedCount(roots.count, endpointRoots.count), of: Double.self))
            for localRoot in roots + endpointRoots {
                try execution.consumeWork(1)
                guard localRoot >= -localRootTolerance,
                      localRoot <= 1.0 + localRootTolerance else {
                    continue
                }
                let refinement = endpointRoots.contains(localRoot)
                    ? RefinedRoot(value: localRoot, iterations: 0) : try refinedLocalRoot(
                    localRoot,
                    coefficients: rootCoefficients,
                    maximumIterations: options.maximumIterations, using: &execution
                )
                let boundedRoot = min(max(refinement.value, 0.0), 1.0)
                let parameter = span.lower
                    + (span.upper - span.lower) * boundedRoot
                guard try contains(
                    parameter,
                    range: options.curveRange,
                    tolerance: curveParameterTolerance, using: &execution
                ) else {
                    continue
                }
                let geometry = try curve.parameterDerivatives(
                    at: parameter,
                    tolerance: tolerance, using: &execution
                )
                var direction = geometry.firstDerivative
                if direction.length == 0, boundedRoot == 0 || boundedRoot == 1 {
                    // Positive rational weights preserve the first nonzero
                    // endpoint control difference's tangent direction.
                    let controls = span.controlPoints
                    let endpoint = boundedRoot == 0 ? controls[0] : controls[controls.count - 1]
                    for offset in controls.indices {
                        try execution.consumeWork(1)
                        let index = boundedRoot == 0 ? offset : controls.count - 1 - offset
                        guard controls[index] != endpoint else { continue }
                        direction = boundedRoot == 0
                            ? controls[index] - endpoint : endpoint - controls[index]
                        break
                    }
                }
                let speed = direction.length
                guard speed.isFinite, speed > 0 else {
                    throw KernelError(
                        phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                        message: "The curve intersection has no resolved tangent direction.")
                }
                let tangent = direction / speed
                let projection = try surface.parameterProjection(
                    of: geometry.position,
                    tolerance: tolerance, using: &execution
                )
                let rangeResolver = SurfaceParameterRangeResolver()
                guard let surfaceU = rangeResolver.resolvedParameter(
                    projection.u,
                    domain: surface.uDomain,
                    requestedRange: options.surfaceURange,
                    tolerance: tolerance
                ),
                let surfaceV = rangeResolver.resolvedParameter(
                    projection.v,
                    domain: surface.vDomain,
                    requestedRange: options.surfaceVRange,
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
                    tolerance: tolerance, using: &execution
                )
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: CurveSurfaceIntersection.self))
                intersections.append(try CurveSurfaceIntersection(
                    point: geometry.position,
                    curveParameter: parameter,
                    surfaceU: surfaceU,
                    surfaceV: surfaceV,
                    kind: abs(tangent.dot(surfaceNormal)) <= tolerance.angle
                        ? .tangent
                        : .transverse,
                    residual: residual,
                    iterations: refinement.iterations
                ))
            }
        }
        return try deduplicated(
            intersections,
            curveParameterTolerance: curveParameterTolerance,
            tolerance: tolerance, using: &execution
        )
    }

    private func implicitPolynomial(
        span: RationalBezierCurvePatch3D,
        surface: CanonicalAnalyticSurface, using execution: inout OriginalQueryExecution
    ) throws -> ImplicitPolynomial {
        try execution.consumeWork(1)
        let curve = try homogeneousCurve(span, using: &execution)
        let weightSquared = try multiplied(curve.weight, curve.weight, using: &execution)
        let coefficients: [Double]
        let referenceTerms: [[Double]]
        switch surface {
        case let .plane(plane):
            let relative = try relativeCurve(curve, to: plane.origin, using: &execution)
            coefficients = try dot(relative, plane.normal, using: &execution)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [Double].self))
            referenceTerms = [coefficients, curve.weight]
        case let .cylinder(cylinder):
            let relative = try relativeCurve(curve, to: cylinder.origin, using: &execution)
            let axial = try dot(relative, cylinder.axis, using: &execution)
            let radial = try subtracting(
                relative,
                try polynomialVector(direction: cylinder.axis, scale: axial, using: &execution), using: &execution
            )
            let radialSquared = try dot(radial, radial, using: &execution)
            let radiusSquared = try scaled(
                weightSquared,
                by: cylinder.radius * cylinder.radius, using: &execution
            )
            coefficients = try subtracting(radialSquared, radiusSquared, using: &execution)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [Double].self))
            referenceTerms = [radialSquared, radiusSquared]
        case let .cone(cone):
            let relative = try relativeCurve(curve, to: cone.apex, using: &execution)
            let axial = try dot(relative, cone.axis, using: &execution)
            let radial = try subtracting(
                relative,
                try polynomialVector(direction: cone.axis, scale: axial, using: &execution), using: &execution
            )
            let axialSquared = try multiplied(axial, axial, using: &execution)
            let radialSquared = try dot(radial, radial, using: &execution)
            let coneSquared = try scaled(
                axialSquared,
                by: pow(tan(cone.halfAngle), 2.0), using: &execution
            )
            coefficients = try subtracting(radialSquared, coneSquared, using: &execution)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [Double].self))
            referenceTerms = [radialSquared, coneSquared]
        case let .sphere(sphere):
            let relative = try relativeCurve(curve, to: sphere.center, using: &execution)
            let squaredDistance = try dot(relative, relative, using: &execution)
            let radiusSquared = try scaled(
                weightSquared,
                by: sphere.radius * sphere.radius, using: &execution
            )
            coefficients = try subtracting(squaredDistance, radiusSquared, using: &execution)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [Double].self))
            referenceTerms = [squaredDistance, radiusSquared]
        case let .torus(torus):
            let relative = try relativeCurve(curve, to: torus.center, using: &execution)
            let axial = try dot(relative, torus.axis, using: &execution)
            let axialSquared = try multiplied(axial, axial, using: &execution)
            let radial = try subtracting(
                relative,
                try polynomialVector(direction: torus.axis, scale: axial, using: &execution), using: &execution
            )
            let radialSquared = try dot(radial, radial, using: &execution)
            let squaredDistance = try adding(radialSquared, axialSquared, using: &execution)
            let implicitQuadratic = try adding(
                squaredDistance,
                try scaled(
                    weightSquared,
                    by: torus.majorRadius * torus.majorRadius
                        - torus.minorRadius * torus.minorRadius, using: &execution
                ), using: &execution
            )
            let firstTerm = try multiplied(
                implicitQuadratic,
                implicitQuadratic, using: &execution
            )
            let secondTerm = try scaled(
                try multiplied(radialSquared, weightSquared, using: &execution),
                by: 4.0 * torus.majorRadius * torus.majorRadius, using: &execution
            )
            coefficients = try subtracting(firstTerm, secondTerm, using: &execution)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [Double].self))
            referenceTerms = [firstTerm, secondTerm]
        case .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "The B-spline curve analytic intersector received a non-analytic surface."
            )
        }
        guard coefficients.isEmpty == false,
              coefficients.allSatisfy({ $0.isFinite }) else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: nil,
                message: "B-spline implicit polynomial exceeded finite arithmetic."
            )
        }
        var referenceScale = 0.0
        for term in referenceTerms {
            for coefficient in term {
                try execution.consumeWork(1)
                referenceScale = max(referenceScale, abs(coefficient))
            }
        }
        return ImplicitPolynomial(coefficients: coefficients, referenceScale: max(referenceScale, 1.0))
    }

    private func homogeneousCurve(
        _ span: RationalBezierCurvePatch3D, using execution: inout OriginalQueryExecution
    ) throws -> HomogeneousCurve {
        try execution.consumeWork(1)
        for _ in 0..<3 { try execution.retainStorage(bytes: exactScalarPayloadBytes(count: span.controlPoints.count, of: Double.self)) }
        return try HomogeneousCurve(
            x: try bernsteinToPower(span.controlPoints.indices.map {
                try execution.consumeWork(1)
                return span.controlPoints[$0].x * span.weights[$0]
            }, using: &execution),
            y: try bernsteinToPower(span.controlPoints.indices.map {
                try execution.consumeWork(1)
                return span.controlPoints[$0].y * span.weights[$0]
            }, using: &execution),
            z: try bernsteinToPower(span.controlPoints.indices.map {
                try execution.consumeWork(1)
                return span.controlPoints[$0].z * span.weights[$0]
            }, using: &execution),
            weight: try bernsteinToPower(span.weights, using: &execution)
        )
    }

    private func relativeCurve(
        _ curve: HomogeneousCurve,
        to origin: Point3D, using execution: inout OriginalQueryExecution
    ) throws -> PolynomialVector3 {
        try execution.consumeWork(1)
        return PolynomialVector3(
            x: try subtracting(curve.x, try scaled(curve.weight, by: origin.x, using: &execution), using: &execution),
            y: try subtracting(curve.y, try scaled(curve.weight, by: origin.y, using: &execution), using: &execution),
            z: try subtracting(curve.z, try scaled(curve.weight, by: origin.z, using: &execution), using: &execution)
        )
    }

    private func dot(
        _ lhs: PolynomialVector3,
        _ rhs: PolynomialVector3, using execution: inout OriginalQueryExecution
    ) throws -> [Double] {
        try execution.consumeWork(1)
        return try adding(
            try adding(
                try multiplied(lhs.x, rhs.x, using: &execution),
                try multiplied(lhs.y, rhs.y, using: &execution), using: &execution
            ),
            try multiplied(lhs.z, rhs.z, using: &execution), using: &execution
        )
    }

    private func dot(
        _ value: PolynomialVector3,
        _ direction: Vector3D, using execution: inout OriginalQueryExecution
    ) throws -> [Double] {
        try execution.consumeWork(1)
        return try adding(
            try adding(
                try scaled(value.x, by: direction.x, using: &execution),
                try scaled(value.y, by: direction.y, using: &execution), using: &execution
            ),
            try scaled(value.z, by: direction.z, using: &execution), using: &execution
        )
    }

    private func polynomialVector(
        direction: Vector3D,
        scale: [Double], using execution: inout OriginalQueryExecution
    ) throws -> PolynomialVector3 {
        try execution.consumeWork(1)
        return PolynomialVector3(
            x: try scaled(scale, by: direction.x, using: &execution),
            y: try scaled(scale, by: direction.y, using: &execution),
            z: try scaled(scale, by: direction.z, using: &execution)
        )
    }

    private func subtracting(
        _ lhs: PolynomialVector3,
        _ rhs: PolynomialVector3, using execution: inout OriginalQueryExecution
    ) throws -> PolynomialVector3 {
        try execution.consumeWork(1)
        return PolynomialVector3(
            x: try subtracting(lhs.x, rhs.x, using: &execution),
            y: try subtracting(lhs.y, rhs.y, using: &execution),
            z: try subtracting(lhs.z, rhs.z, using: &execution)
        )
    }

    private func implicitNormal(
        at point: Point3D,
        surface: CanonicalAnalyticSurface,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Vector3D {
        try execution.consumeWork(1)
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
                code: .invalidInput,
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
        surface: CanonicalAnalyticSurface, using execution: inout OriginalQueryExecution
    ) throws -> Int {
        try execution.consumeWork(1)
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
                code: .invalidInput,
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

    private func multiplied(_ lhs: [Double], _ rhs: [Double], using execution: inout OriginalQueryExecution) throws -> [Double] {
        let sum = lhs.count.addingReportingOverflow(rhs.count)
        guard !sum.overflow, sum.partialValue > 0 else { throw ExactScalarFailure.countOverflow }
        let count = sum.partialValue - 1
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Double.self))
        var result = Array(repeating: 0.0, count: count)
        for lhsIndex in lhs.indices {
            for rhsIndex in rhs.indices {
                try execution.consumeWork(1)
                result[lhsIndex + rhsIndex] += lhs[lhsIndex] * rhs[rhsIndex]
            }
        }
        return result
    }

    private func adding(_ lhs: [Double], _ rhs: [Double], using execution: inout OriginalQueryExecution) throws -> [Double] {
        let count = max(lhs.count, rhs.count)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Double.self))
        return try (0..<count).map {
            try execution.consumeWork(1)
            return ($0 < lhs.count ? lhs[$0] : 0.0) + ($0 < rhs.count ? rhs[$0] : 0.0)
        }
    }

    private func subtracting(_ lhs: [Double], _ rhs: [Double], using execution: inout OriginalQueryExecution) throws -> [Double] {
        try adding(lhs, scaled(rhs, by: -1.0, using: &execution), using: &execution)
    }

    private func scaled(_ polynomial: [Double], by scale: Double, using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: polynomial.count, of: Double.self))
        return try polynomial.map {
            try execution.consumeWork(1)
            return $0 * scale
        }
    }

    private func refinedLocalRoot(
        _ initial: Double,
        coefficients: [Double],
        maximumIterations: Int, using execution: inout OriginalQueryExecution
    ) throws -> RefinedRoot {
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: max(0, coefficients.count - 1), of: Double.self))
        let derivative = try coefficients.indices.dropFirst().map { index in
            try execution.consumeWork(1)
            return coefficients[index] * Double(index)
        }
        var coefficientScale = 0.0
        for coefficient in coefficients {
            try execution.consumeWork(1)
            coefficientScale = max(coefficientScale, abs(coefficient))
        }
        coefficientScale = max(coefficientScale, 1.0)
        let arithmeticTolerance = coefficientScale * Double.ulpOfOne * 256.0
        var value = min(max(initial, 0.0), 1.0)
        var iterationCount = 0
        for iteration in 0..<maximumIterations {
            let residual = try evaluate(coefficients, at: value, using: &execution)
            guard abs(residual) > arithmeticTolerance else { break }
            let slope = try evaluate(derivative, at: value, using: &execution)
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

    private func evaluate(_ coefficients: [Double], at value: Double, using execution: inout OriginalQueryExecution) throws -> Double {
        var partial = 0.0
        for coefficient in coefficients.reversed() {
            try execution.consumeWork(1)
            partial = partial * value + coefficient
        }
        return partial
    }

    private func parameterTolerance(
        for domain: ParameterDomain,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double {
        try execution.consumeWork(1)
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
        tolerance: Double, using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        try execution.consumeWork(1)
        guard let range else { return true }
        return value >= range.lower - tolerance
            && value <= range.upper + tolerance
    }

    private func overlaps(
        lower: Double,
        upper: Double,
        range: ScalarInterval?,
        tolerance: Double, using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        try execution.consumeWork(1)
        guard let range else { return true }
        return lower <= range.upper + tolerance
            && range.lower <= upper + tolerance
    }

    private func bernsteinToPower(_ coefficients: [Double], using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        guard coefficients.isEmpty == false,
              coefficients.allSatisfy({ $0.isFinite }) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "Bernstein coefficients must be finite and non-empty."
            )
        }
        let degree = coefficients.count - 1
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: coefficients.count, of: Double.self))
        var result = Array(repeating: 0.0, count: coefficients.count)
        for power in 0...degree {
            let outer = try binomialCoefficient(degree, power, using: &execution)
            var sum = 0.0
            for index in 0...power {
                let inner = try binomialCoefficient(power, index, using: &execution)
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

    private func binomialCoefficient(_ n: Int, _ k: Int, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let count = min(k, n - k)
        guard count > 0 else {
            return 1.0
        }
        var result = 1.0
        for index in 1...count {
            try execution.consumeWork(1)
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [CurveSurfaceIntersection] {
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: intersections.count, of: CurveSurfaceIntersection.self))
        let sorted = try intersections.sorted {
            try execution.consumeWork(1)
            return $0.curveParameter < $1.curveParameter
        }
        var result: [CurveSurfaceIntersection] = []
        for intersection in sorted {
            if let index = try result.firstIndex(where: {
                try execution.consumeWork(1)
                return abs($0.curveParameter - intersection.curveParameter)
                    <= curveParameterTolerance
                    && ($0.point - intersection.point).length <= tolerance.distance
            }) {
                if intersection.residual < result[index].residual {
                    result[index] = intersection
                }
            } else {
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: CurveSurfaceIntersection.self))
                result.append(intersection)
            }
        }
        return result
    }

    private func checkedCount(_ lhs: Int, _ rhs: Int) throws -> Int {
        let count = lhs.addingReportingOverflow(rhs)
        guard !count.overflow else { throw ExactScalarFailure.countOverflow }
        return count.partialValue
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
