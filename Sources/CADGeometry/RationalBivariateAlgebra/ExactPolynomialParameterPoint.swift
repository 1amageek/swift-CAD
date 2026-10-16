import CADCore

/// A retained original polynomial parameter point, with exact source signs.
package struct ExactPolynomialParameterPoint: Sendable {
    package let u: ExactBivariatePolynomial
    package let v: ExactBivariatePolynomial
    package let parameter: ExactMonotoneGraphEndpoint
    package let originalDomain: SurfaceParameterBox

    package func hasSameCoordinates<B: ExactScalarAdmission & ~Copyable>(as other: Self,
        maximumDepth: Int, usage: inout B) throws -> Bool {
        try RationalAlgebraStorage.retain(2, of: (ExactBivariatePolynomial, ExactBivariatePolynomial).self, usage: &usage)
        for (first, second) in [(u, other.u), (v, other.v)] {
            try usage.consumeWork(1)
            let a = try OriginalPolynomialCoordinateRoot.coordinate(first, at: parameter,
                maximumDepth: maximumDepth, usage: &usage)
            let b = try OriginalPolynomialCoordinateRoot.coordinate(second, at: other.parameter,
                maximumDepth: maximumDepth, usage: &usage)
            guard try a.hasSameValue(as: b, maximumDepth: maximumDepth, usage: &usage) else { return false }
        }
        return true
    }

    package func sign<B: ExactScalarAdmission & ~Copyable>(of original: ExactBivariatePolynomial,
        maximumDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        try parameter.sign(of: original.composed(withU: u, v: v, usage: &usage),
            maximumDepth: maximumDepth, usage: &usage)
    }

    package func coordinateIs<B: ExactScalarAdmission & ~Copyable>(_ endpoint: ExactMonotoneGraphEndpoint,
        alongU: Bool, maximumDepth: Int, usage: inout B) throws -> Bool {
        let coordinate = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
        switch endpoint {
        case .authored(let station):
            let difference = try coordinate.subtracting(.constant(station, usage: &usage), usage: &usage)
            if case .zero = try sign(of: difference, maximumDepth: maximumDepth, usage: &usage) { return true }
            return false
        case .algebraic(let root):
            let equation = alongU ? root.polynomial : try root.polynomial.exchangedAxes(usage: &usage)
            guard case .zero = try sign(of: equation, maximumDepth: maximumDepth, usage: &usage) else { return false }
            let low = try coordinate.subtracting(.constant(root.isolation.lower, usage: &usage), usage: &usage)
            let high = try coordinate.subtracting(.constant(root.isolation.upper, usage: &usage), usage: &usage)
            switch try sign(of: low, maximumDepth: maximumDepth, usage: &usage) {
            case .negative: return false
            case .zero: if root.isolation.excludesLowerEndpoint { return false }
            case .positive: break
            }
            switch try sign(of: high, maximumDepth: maximumDepth, usage: &usage) {
            case .positive: return false
            case .zero: if root.isolation.excludesUpperEndpoint { return false }
            case .negative: break
            }
            return true
        }
    }

    package func isInside<B: ExactScalarAdmission & ~Copyable>(_ domain: SurfaceParameterBox,
        maximumDepth: Int, usage: inout B) throws -> Bool {
        for alongU in [true, false] {
            let bounds = alongU ? domain.u : domain.v
            let coordinate = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
            let lower = try coordinate.subtracting(.constant(.originalDouble(bounds.lower, usage: &usage), usage: &usage), usage: &usage)
            let upper = try coordinate.subtracting(.constant(.originalDouble(bounds.upper, usage: &usage), usage: &usage), usage: &usage)
            if case .negative = try sign(of: lower, maximumDepth: maximumDepth, usage: &usage) { return false }
            if case .positive = try sign(of: upper, maximumDepth: maximumDepth, usage: &usage) { return false }
        }
        return true
    }

    package func enclosure<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> SurfaceParameterBox {
        let low = try parameter.lower.outwardInterval(usage: &usage)
        let high = try parameter.upper.outwardInterval(usage: &usage)
        let free = try ScalarInterval(lower: low.lower, upper: high.upper)
        let zero = try ScalarInterval(lower: 0, upper: 0)
        let box = SurfaceParameterBox(u: free, v: zero)
        let ub = try u.enclosure(over: box, usage: &usage), vb = try v.enclosure(over: box, usage: &usage)
        return try SurfaceParameterBox(
            u: ScalarInterval(lower: max(originalDomain.u.lower, ub.lower), upper: min(originalDomain.u.upper, ub.upper)),
            v: ScalarInterval(lower: max(originalDomain.v.lower, vb.lower), upper: min(originalDomain.v.upper, vb.upper)))
    }

    package func refined<B: ExactScalarAdmission & ~Copyable>(maximumUWidth: Double, maximumVWidth: Double,
        maximumDepth: Int, usage: inout B) throws -> Self {
        guard maximumUWidth.isFinite, maximumVWidth.isFinite, maximumUWidth > 0, maximumVWidth > 0 else {
            throw rationalAlgebraFailure("Original polynomial point refinement needs positive native widths.")
        }
        var current = self
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        while true {
            let box = try current.enclosure(usage: &usage)
            if box.u.width <= maximumUWidth, box.v.width <= maximumVWidth { return current }
            let width = try current.parameter.upper.subtracting(current.parameter.lower, usage: &usage)
            guard width.isPositive else {
                throw rationalAlgebraFailure("Original polynomial point has exhausted native binary enclosure resolution.")
            }
            current = try Self(u: u, v: v, parameter: current.parameter.refined(
                maximumWidth: width.divided(by: two, usage: &usage), maximumDepth: maximumDepth, usage: &usage),
                originalDomain: originalDomain)
        }
    }
}
