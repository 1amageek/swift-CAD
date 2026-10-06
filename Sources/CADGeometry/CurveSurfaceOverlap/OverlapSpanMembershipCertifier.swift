import CADCore
import Foundation

/// Bounds the implicit residual over a complete positive-weight rational span.
struct OverlapSpanMembershipCertifier {
    private typealias Polynomial = [OutwardScalarInterval]
    private typealias VectorPolynomial = (x: Polynomial, y: Polynomial, z: Polynomial)
    let maximumDegree: Int
    let tolerance: ModelingTolerance

    func deviation(of span: RationalBezierCurvePatch3D, on surface: CanonicalAnalyticSurface) throws -> Double {
        let degree = span.controlPoints.count - 1
        let factor: Int
        switch surface { case .plane: factor = 1; case .torus: factor = 4; default: factor = 2 }
        guard degree <= maximumDegree / factor else { throw failure(.resourceLimitExceeded, "Overlap implicit polynomial exceeds the degree budget.") }
        let weight = span.weights.map(OutwardScalarInterval.exact)
        let origin: Point3D
        switch surface {
        case .plane(let value): origin = value.origin
        case .cylinder(let value): origin = value.origin
        case .cone(let value): origin = value.apex
        case .sphere(let value): origin = value.center
        case .torus(let value): origin = value.center
        case .unsupported: throw failure(.unsupportedCapability, "Overlap membership requires an analytic implicit support.")
        }
        func coordinate(_ get: (Point3D) -> Double) -> Polynomial {
            span.controlPoints.indices.map {
                (OutwardScalarInterval.exact(get(span.controlPoints[$0])) - .exact(get(origin))) * weight[$0]
            }
        }
        let relative: VectorPolynomial = (coordinate { $0.x }, coordinate { $0.y }, coordinate { $0.z })
        let numerator: Polynomial
        var metricDenominator = OutwardScalarInterval.exact(1)
        var usesSquareRoot = false
        switch surface {
        case .plane(let plane):
            numerator = dot(relative, plane.normal)
            metricDenominator = OutwardScalarInterval(plane.normal.length)
        case .sphere(let sphere):
            numerator = subtract(try squared(relative), scale(try multiply(weight, weight), by: .exact(sphere.radius) * .exact(sphere.radius)))
            metricDenominator = .exact(sphere.radius)
        case .cylinder(let cylinder):
            let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
            let axial = dot(relative, axis)
            let radial = subtract(relative, vector(axis, scale: axial))
            numerator = subtract(try squared(radial), scale(try multiply(weight, weight), by: .exact(cylinder.radius) * .exact(cylinder.radius)))
            metricDenominator = .exact(cylinder.radius)
        case .cone(let cone):
            let axis = try cone.axis.normalized(tolerance: tolerance.distance)
            let axial = dot(relative, axis)
            let radial = subtract(relative, vector(axis, scale: axial))
            let tangent = OutwardScalarInterval.exact(tan(cone.halfAngle))
            numerator = subtract(try squared(radial), scale(try multiply(axial, axial), by: tangent * tangent))
            usesSquareRoot = true
        case .torus(let torus):
            let axis = try torus.axis.normalized(tolerance: tolerance.distance)
            let axial = dot(relative, axis)
            let radial = subtract(relative, vector(axis, scale: axial))
            let radialSquared = try squared(radial)
            let weightSquared = try multiply(weight, weight)
            let majorSquared = OutwardScalarInterval.exact(torus.majorRadius) * .exact(torus.majorRadius)
            let minorSquared = OutwardScalarInterval.exact(torus.minorRadius) * .exact(torus.minorRadius)
            let quadratic = add(try squared(relative), scale(weightSquared, by: majorSquared - minorSquared))
            numerator = subtract(try multiply(quadratic, quadratic), scale(try multiply(radialSquared, weightSquared), by: .exact(4) * majorSquared))
            metricDenominator = .exact(torus.minorRadius) * (majorSquared - minorSquared)
        case .unsupported:
            throw failure(.unsupportedCapability, "Overlap membership has no implicit support.")
        }
        guard let minimumWeight = span.weights.min(), minimumWeight > 0 else {
            throw failure(.singularGeometry, "Overlap rational weights must remain positive.")
        }
        var denominator = metricDenominator
        for _ in 0..<factor { denominator = denominator * .exact(minimumWeight) }
        let magnitude = numerator.map(\.absoluteUpperBound).max() ?? .infinity
        guard magnitude.isFinite, denominator.isFinite, denominator.lower > 0,
              let residual = OutwardScalarInterval.exact(magnitude).divided(by: denominator), residual.isFinite else {
            throw failure(.resourceLimitExceeded, "Overlap residual certification exceeded finite interval arithmetic.")
        }
        let bound = usesSquareRoot ? sqrt(max(0, residual.upper)).nextUp : residual.upper
        guard bound.isFinite else { throw failure(.resourceLimitExceeded, "Overlap distance bound is not finite.") }
        return max(0, bound)
    }

    private func add(_ lhs: Polynomial, _ rhs: Polynomial) -> Polynomial {
        zip(lhs, rhs).map { $0.0 + $0.1 }
    }
    private func subtract(_ lhs: Polynomial, _ rhs: Polynomial) -> Polynomial {
        zip(lhs, rhs).map { $0.0 - $0.1 }
    }
    private func scale(_ value: Polynomial, by scalar: OutwardScalarInterval) -> Polynomial {
        value.map { $0 * scalar }
    }
    private func vector(_ direction: Vector3D, scale value: Polynomial) -> VectorPolynomial {
        (scale(value, by: .exact(direction.x)), scale(value, by: .exact(direction.y)), scale(value, by: .exact(direction.z)))
    }
    private func subtract(_ lhs: VectorPolynomial, _ rhs: VectorPolynomial) -> VectorPolynomial {
        (subtract(lhs.x, rhs.x), subtract(lhs.y, rhs.y), subtract(lhs.z, rhs.z))
    }
    private func dot(_ value: VectorPolynomial, _ direction: Vector3D) -> Polynomial {
        add(add(scale(value.x, by: .exact(direction.x)), scale(value.y, by: .exact(direction.y))), scale(value.z, by: .exact(direction.z)))
    }
    private func squared(_ value: VectorPolynomial) throws -> Polynomial {
        try add(add(multiply(value.x, value.x), multiply(value.y, value.y)), multiply(value.z, value.z))
    }

    private func multiply(_ lhs: Polynomial, _ rhs: Polynomial) throws -> Polynomial {
        let m = lhs.count - 1, n = rhs.count - 1
        guard m + n <= maximumDegree else { throw failure(.resourceLimitExceeded, "Overlap Bernstein product exceeds its degree budget.") }
        let left = try binomials(m), right = try binomials(n), output = try binomials(m + n)
        var result = Polynomial(repeating: .exact(0), count: m + n + 1)
        for k in result.indices {
            try Task.checkCancellation()
            for i in max(0, k - n)...min(m, k) {
                let j = k - i
                guard let factor = (left[i] * right[j]).divided(by: output[k]) else {
                    throw failure(.resourceLimitExceeded, "Overlap Bernstein product lost its positive normalization.")
                }
                result[k] = result[k] + lhs[i] * rhs[j] * factor
            }
            guard result[k].isFinite else { throw failure(.resourceLimitExceeded, "Overlap Bernstein arithmetic is not finite.") }
        }
        return result
    }

    private func binomials(_ degree: Int) throws -> Polynomial {
        var result: Polynomial = [.exact(1)]
        guard degree > 0 else { return result }
        for index in 1...degree {
            guard let next = (result[index - 1] * .exact(Double(degree - index + 1))).divided(by: .exact(Double(index))), next.isFinite else {
                throw failure(.resourceLimitExceeded, "Overlap Bernstein normalization is not finite.")
            }
            result.append(next)
        }
        return result
    }

    private func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
