import CADCore

/// A retained original regular graph endpoint with exact native-coordinate signs.
package struct ExactMonotoneGraphPoint: Sendable {
    package let original: ExactBivariatePolynomial
    package let sourceDomain: SurfaceParameterBox
    package let freeAlongU: Bool
    package let freeEndpoint: ExactMonotoneGraphEndpoint
    private let parameters: ExactAlgebraicParameterPair

    package init<B: ExactScalarAdmission & ~Copyable>(original: ExactBivariatePolynomial,
        over domain: SurfaceParameterBox, freeAlongU: Bool, endpoint: ExactMonotoneGraphEndpoint,
        maximumDepth: Int, usage: inout B) throws {
        let transverseDerivative = try original.differentiated(alongU: !freeAlongU, usage: &usage)
            .enclosure(over: domain, usage: &usage)
        guard transverseDerivative.excludesZero else {
            throw rationalAlgebraFailure("Original graph endpoint has no whole transverse uniqueness certificate.")
        }
        let root: ExactAlgebraicRealRoot
        switch endpoint {
        case .algebraic(let value): root = value
        case .authored(let value):
            let equation = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
                .subtracting(.constant(value, usage: &usage), usage: &usage)
            root = try ExactAlgebraicRealRoot(polynomial: equation,
                isolation: .init(lower: value, upper: value, isRationalStation: true,
                    isolationDepth: endpoint.depth, excludesLowerEndpoint: false,
                    excludesUpperEndpoint: false), usage: &usage)
        }
        let orientedSource = freeAlongU ? original : try original.exchangedAxes(usage: &usage)
        let orientedDomain = freeAlongU ? domain : SurfaceParameterBox(u: domain.v, v: domain.u)
        let fiber = try ExactAlgebraicFiberPolynomial(source: orientedSource, at: root,
            maximumDepth: maximumDepth, usage: &usage)
        let roots = try ExactAlgebraicFiberRootIsolator.isolate(fiber,
            lower: .originalDouble(orientedDomain.v.lower, usage: &usage),
            upper: .originalDouble(orientedDomain.v.upper, usage: &usage),
            maximumDepth: maximumDepth, usage: &usage)
        guard roots.count == 1, let transverseRoot = roots.first else {
            throw rationalAlgebraFailure("Original regular endpoint does not have exactly one transverse root in its source rectangle.")
        }
        self.original = original; sourceDomain = domain; self.freeAlongU = freeAlongU
        freeEndpoint = endpoint
        parameters = ExactAlgebraicParameterPair(projectionRoot: root, fiber: fiber,
            fiberRoot: transverseRoot, sourceDomain: orientedDomain)
    }

    package func enclosure<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> SurfaceParameterBox {
        let box = try parameters.enclosure(usage: &usage)
        return freeAlongU ? box : SurfaceParameterBox(u: box.v, v: box.u)
    }

    package func sign<B: ExactScalarAdmission & ~Copyable>(of expression: ExactBivariatePolynomial,
        maximumDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        let native = freeAlongU ? expression : try expression.exchangedAxes(usage: &usage)
        return try parameters.sign(of: native, maximumDepth: maximumDepth, usage: &usage)
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

    package func dependentCoordinateIsSame<B: ExactScalarAdmission & ~Copyable>(as other: Self,
        maximumDepth: Int, usage: inout B) throws -> Bool {
        guard freeAlongU == other.freeAlongU,
            try freeEndpoint.hasSameValue(as: other.freeEndpoint,
                maximumDepth: maximumDepth, usage: &usage) else { return false }
        let otherSource = freeAlongU ? other.original : try other.original.exchangedAxes(usage: &usage)
        let rebased = try ExactAlgebraicFiberPolynomial(source: otherSource, at: parameters.projectionRoot,
            maximumDepth: maximumDepth, usage: &usage)
        let common = try ExactAlgebraicFiberPolynomial.gcd(parameters.fiber, rebased,
            maximumDepth: maximumDepth, usage: &usage)
        guard common.degree > 0 else { return false }
        let a = parameters.fiberRoot, b = other.parameters.fiberRoot
        let lower: ExactRationalCoefficient, upper: ExactRationalCoefficient
        let excludesLower: Bool, excludesUpper: Bool
        let lowerOrder = try a.lower.subtracting(b.lower, usage: &usage)
        if lowerOrder.isPositive { lower = a.lower; excludesLower = a.excludesLower }
        else if lowerOrder.isNegative { lower = b.lower; excludesLower = b.excludesLower }
        else { lower = a.lower; excludesLower = a.excludesLower || b.excludesLower }
        let upperOrder = try a.upper.subtracting(b.upper, usage: &usage)
        if upperOrder.isNegative { upper = a.upper; excludesUpper = a.excludesUpper }
        else if upperOrder.isPositive { upper = b.upper; excludesUpper = b.excludesUpper }
        else { upper = a.upper; excludesUpper = a.excludesUpper || b.excludesUpper }
        if try upper.subtracting(lower, usage: &usage).isNegative { return false }
        let sequence = try ExactAlgebraicFiberSturmSequence(common, maximumDepth: maximumDepth, usage: &usage)
        return try sequence.count(lower: lower, upper: upper, excludesLower: excludesLower,
            excludesUpper: excludesUpper, maximumDepth: maximumDepth, usage: &usage) == 1
    }

}
