import CADCore

/// Exact original station or regular fiber retained by a complete plane atlas.
struct SurfaceSilhouetteAtlasEndpoint: Sendable {
    enum Location: Sendable {
        case station(ExactBivariateSystemRoot, completeHalfBranchCount: Int)
        case fiber(ExactRationalCoefficient, ExactAlgebraicRealRoot)
    }
    let original: ExactBivariatePolynomial
    let location: Location

    func originalFieldParameters(usage: inout OriginalQueryExecution)
        throws -> (u: OriginalSingularFieldElement, v: OriginalSingularFieldElement) {
        switch location {
        case .station(let root, _):
            let context = try OriginalSingularFieldContext(original: root, usage: &usage)
            let u = try OriginalSingularFieldElement.original(.coordinate(alongU: true, usage: &usage),
                in: context, usage: &usage)
            let v = try OriginalSingularFieldElement.original(.coordinate(alongU: false, usage: &usage),
                in: context, usage: &usage)
            return (u, v)
        case .fiber(let u, let root):
            let context = try OriginalSingularFieldContext(usage: &usage)
            let v = try OriginalSingularFieldRoot.retaining(root, in: context,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage).value(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            return (try .constant(u, in: v.context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage), v)
        }
    }

    func sign(of expression: ExactBivariatePolynomial, usage: inout OriginalQueryExecution)
        throws -> ExactAlgebraicRealRoot.Sign {
        switch location {
        case .station(let root, _):
            return try root.sign(of: expression, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        case .fiber(let u, let v):
            let substituted = try expression.restricted(alongU: true, station: u, usage: &usage)
            return try v.sign(of: substituted, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        }
    }

    func hasSameValue(as other: Self, usage: inout OriginalQueryExecution) throws -> Bool {
        switch (location, other.location) {
        case (.station(let a, _), .station(let b, _)):
            return try a.hasSameValue(as: b, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        case (.fiber(let u, let v), .fiber(let x, let y)):
            guard u == x else { return false }
            return try ExactMonotoneGraphEndpoint.algebraic(v).hasSameValue(as: .algebraic(y),
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        case (.station, .fiber(let u, let v)):
            return try matches(u: u, v: v, usage: &usage)
        case (.fiber, .station):
            return try other.hasSameValue(as: self, usage: &usage)
        }
    }

    func hasSameValue(as point: ExactMonotoneGraphPoint, usage: inout OriginalQueryExecution) throws -> Bool {
        switch location {
        case .fiber(let u, let v):
            return try point.coordinateIs(.authored(u), alongU: true,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                && point.coordinateIs(.algebraic(v), alongU: false,
                    maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        case .station:
            guard try coordinateIs(point.freeEndpoint, alongU: point.freeAlongU, usage: &usage),
                case .zero = try sign(of: point.original, usage: &usage) else { return false }
            // Whole transverse uniqueness of the issued original graph makes
            // its retained root the only source zero inside this closed box.
            for axis in 0..<2 {
                let alongU = axis == 0
                let bounds = alongU ? point.sourceDomain.u : point.sourceDomain.v
                let coordinate = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
                let low = try coordinate.subtracting(.constant(.originalDouble(bounds.lower, usage: &usage), usage: &usage), usage: &usage)
                let high = try coordinate.subtracting(.constant(.originalDouble(bounds.upper, usage: &usage), usage: &usage), usage: &usage)
                if case .negative = try sign(of: low, usage: &usage) { return false }
                if case .positive = try sign(of: high, usage: &usage) { return false }
            }
            return true
        }
    }

    func hasSameValue(as point: ExactPolynomialParameterPoint, usage: inout OriginalQueryExecution) throws -> Bool {
        let u = try OriginalPolynomialCoordinateRoot.coordinate(point.u, at: point.parameter,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let v = try OriginalPolynomialCoordinateRoot.coordinate(point.v, at: point.parameter,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        return try coordinateIs(u, alongU: true, usage: &usage)
            && coordinateIs(v, alongU: false, usage: &usage)
    }

    private func coordinateIs(_ endpoint: ExactMonotoneGraphEndpoint, alongU: Bool,
        usage: inout OriginalQueryExecution) throws -> Bool {
        let coordinate = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
        switch endpoint {
        case .authored(let value):
            let difference = try coordinate.subtracting(.constant(value, usage: &usage), usage: &usage)
            if case .zero = try sign(of: difference, usage: &usage) { return true }
            return false
        case .algebraic(let root):
            let equation = alongU ? root.polynomial : try root.polynomial.exchangedAxes(usage: &usage)
            guard case .zero = try sign(of: equation, usage: &usage) else { return false }
            let lower = try coordinate.subtracting(.constant(root.isolation.lower, usage: &usage), usage: &usage)
            let upper = try coordinate.subtracting(.constant(root.isolation.upper, usage: &usage), usage: &usage)
            switch try sign(of: lower, usage: &usage) {
            case .negative: return false
            case .zero: if root.isolation.excludesLowerEndpoint { return false }
            case .positive: break
            }
            switch try sign(of: upper, usage: &usage) {
            case .positive: return false
            case .zero: if root.isolation.excludesUpperEndpoint { return false }
            case .negative: break
            }
            return true
        }
    }

    func certifiesStationIncidence(with other: Self, usage: inout OriginalQueryExecution) throws -> Bool {
        guard original == other.original,
            case .station(_, let first) = location,
            case .station(_, let second) = other.location,
            first > 0, first == second else { return false }
        return try hasSameValue(as: other, usage: &usage)
    }

    func isSingularStation(usage: inout OriginalQueryExecution) throws -> Bool {
        guard case .station = location else { return false }
        let u = try original.differentiated(alongU: true, usage: &usage)
        let v = try original.differentiated(alongU: false, usage: &usage)
        if case .zero = try sign(of: u, usage: &usage),
            case .zero = try sign(of: v, usage: &usage) { return true }
        return false
    }

    func coordinateEquals(_ value: Double, alongU: Bool, usage: inout OriginalQueryExecution) throws -> Bool {
        try coordinateIs(.authored(.originalDouble(value, usage: &usage)), alongU: alongU, usage: &usage)
    }

    func hasSameValue(as other: Self, translatingOther translation: (alongU: Bool, amount: ExactRationalCoefficient),
        usage: inout OriginalQueryExecution) throws -> Bool {
        func transportedSign(_ expression: ExactBivariatePolynomial, usage: inout OriginalQueryExecution)
            throws -> ExactAlgebraicRealRoot.Sign {
            try sign(of: OriginalSurfaceSilhouetteField.transported(expression,
                translation: translation, usage: &usage), usage: &usage)
        }
        let u = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
        let v = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
        let projection: ExactBivariatePolynomial, fiber: ExactBivariatePolynomial
        let uLower: ExactRationalCoefficient, uUpper: ExactRationalCoefficient
        let vLower: ExactRationalCoefficient, vUpper: ExactRationalCoefficient
        let uExcludeLower: Bool, uExcludeUpper: Bool, vExcludeLower: Bool, vExcludeUpper: Bool
        switch other.location {
        case .fiber(let x, let y):
            projection = try u.subtracting(.constant(x, usage: &usage), usage: &usage)
            fiber = try y.polynomial.exchangedAxes(usage: &usage)
            uLower = x; uUpper = x; uExcludeLower = false; uExcludeUpper = false
            vLower = y.isolation.lower; vUpper = y.isolation.upper
            vExcludeLower = y.isolation.excludesLowerEndpoint; vExcludeUpper = y.isolation.excludesUpperEndpoint
        case .station(let root, _):
            projection = root.projectionRoot.polynomial
            fiber = try root.originalFiberNumerator(usage: &usage)
            uLower = root.projectionRoot.isolation.lower; uUpper = root.projectionRoot.isolation.upper
            uExcludeLower = root.uExcludesLowerEndpoint; uExcludeUpper = root.uExcludesUpperEndpoint
            vLower = root.fiberRoot.lower; vUpper = root.fiberRoot.upper
            vExcludeLower = root.vExcludesLowerEndpoint; vExcludeUpper = root.vExcludesUpperEndpoint
        }
        guard case .zero = try transportedSign(projection, usage: &usage),
            case .zero = try transportedSign(fiber, usage: &usage) else { return false }
        func inside(_ coordinate: ExactBivariatePolynomial, lower: ExactRationalCoefficient,
            upper: ExactRationalCoefficient, excludesLower: Bool, excludesUpper: Bool,
            usage: inout OriginalQueryExecution) throws -> Bool {
            let lo = try coordinate.subtracting(.constant(lower, usage: &usage), usage: &usage)
            let hi = try coordinate.subtracting(.constant(upper, usage: &usage), usage: &usage)
            switch try transportedSign(lo, usage: &usage) {
            case .negative: return false
            case .zero: if excludesLower { return false }
            case .positive: break
            }
            switch try transportedSign(hi, usage: &usage) {
            case .positive: return false
            case .zero: if excludesUpper { return false }
            case .negative: break
            }
            return true
        }
        return try inside(u, lower: uLower, upper: uUpper, excludesLower: uExcludeLower,
            excludesUpper: uExcludeUpper, usage: &usage)
            && inside(v, lower: vLower, upper: vUpper, excludesLower: vExcludeLower,
                excludesUpper: vExcludeUpper, usage: &usage)
    }

    private func matches(u: ExactRationalCoefficient, v: ExactAlgebraicRealRoot,
        usage: inout OriginalQueryExecution) throws -> Bool {
        let x = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
            .subtracting(.constant(u, usage: &usage), usage: &usage)
        guard case .zero = try sign(of: x, usage: &usage),
            case .zero = try sign(of: v.polynomial.exchangedAxes(usage: &usage), usage: &usage) else { return false }
        let y = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
        let low = try y.subtracting(.constant(v.isolation.lower, usage: &usage), usage: &usage)
        let high = try y.subtracting(.constant(v.isolation.upper, usage: &usage), usage: &usage)
        switch try sign(of: low, usage: &usage) {
        case .negative: return false
        case .zero: if v.isolation.excludesLowerEndpoint { return false }
        case .positive: break
        }
        switch try sign(of: high, usage: &usage) {
        case .positive: return false
        case .zero: if v.isolation.excludesUpperEndpoint { return false }
        case .negative: break
        }
        return true
    }
}
