extension OriginalSingularFieldRoot {
    /// Use the original rational sign authority whenever both retained laws are rational.
    func rationalSign<B: RationalAlgebraAdmitting>(of expression: OriginalSingularFieldPolynomial,
        maximumDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign? {
        func rationalPolynomial(_ source: OriginalSingularFieldPolynomial,
            usage: inout B) throws -> ExactBivariatePolynomial? {
            var coefficients: [ExactBivariatePolynomial.Power: ExactRationalCoefficient] = [:]
            for (power, coefficient) in source.coefficients.enumerated() {
                try usage.consumeExactWork(1)
                guard let value = try coefficient.rationalValue(usage: &usage) else { return nil }
                if value.isZero { continue }
                try RationalAlgebraStorage.retain(1,
                    of: (ExactBivariatePolynomial.Power, ExactRationalCoefficient).self, usage: &usage)
                coefficients[try .init(u: power, v: 0)] = value
            }
            return ExactBivariatePolynomial(coefficients)
        }
        guard let evaluated = try rationalPolynomial(expression, usage: &usage) else { return nil }
        var admission = OriginalScalarRootDomainAdmission(base: usage, domain: admissionDomain)
        defer { usage = admission.base }
        guard let issued = try retainedRationalRoot ?? rationalAuthority(usage: &admission) else { return nil }
        let retained = try issued.retainingIsolation(.init(lower: isolation.lower, upper: isolation.upper,
            isRationalStation: isolation.lower == isolation.upper, isolationDepth: isolation.depth,
            excludesLowerEndpoint: isolation.excludesLower, excludesUpperEndpoint: isolation.excludesUpper), usage: &admission)
        return try retained.sign(of: evaluated, maximumDepth: maximumDepth, usage: &admission)
    }

    func rationalAuthority<B: RationalAlgebraAdmitting>(usage: inout B) throws -> ExactAlgebraicRealRoot? {
        var coefficients: [ExactBivariatePolynomial.Power: ExactRationalCoefficient] = [:]
        for (power, coefficient) in polynomial.coefficients.enumerated() {
            try usage.consumeExactWork(1)
            guard let value = try coefficient.rationalValue(usage: &usage) else { return nil }
            if value.isZero { continue }
            try RationalAlgebraStorage.retain(1,
                of: (ExactBivariatePolynomial.Power, ExactRationalCoefficient).self, usage: &usage)
            coefficients[try .init(u: power, v: 0)] = value
        }
        return try ExactAlgebraicRealRoot(polynomial: ExactBivariatePolynomial(coefficients),
            isolation: .init(lower: isolation.lower, upper: isolation.upper,
                isRationalStation: isolation.lower == isolation.upper, isolationDepth: isolation.depth,
                excludesLowerEndpoint: isolation.excludesLower, excludesUpperEndpoint: isolation.excludesUpper), usage: &usage)
    }

    /// Reuses rational Newton localization without changing the retained original field law.
    func rationalRefinedOnce<B: RationalAlgebraAdmitting>(maximumDepth: Int, forSeparation: Bool,
        usage: inout B) throws -> Self? {
        var admission = OriginalScalarRootDomainAdmission(base: usage, domain: admissionDomain)
        defer { usage = admission.base }
        guard let issued = try retainedRationalRoot ?? rationalAuthority(usage: &admission) else { return nil }
        let retained = try issued.retainingIsolation(.init(lower: isolation.lower, upper: isolation.upper,
            isRationalStation: isolation.lower == isolation.upper, isolationDepth: isolation.depth,
            excludesLowerEndpoint: isolation.excludesLower, excludesUpperEndpoint: isolation.excludesUpper), usage: &admission)
        let width = try isolation.upper.subtracting(isolation.lower, usage: &admission)
            .divided(by: .natural(2, usage: &admission), usage: &admission)
        let refined = try forSeparation
            ? retained.refinedForSeparation(maximumWidth: width, maximumDepth: maximumDepth, usage: &admission)
            : retained.refined(maximumWidth: width, maximumDepth: maximumDepth, usage: &admission)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &admission)
        return retainingRationalIsolation(refined)
    }
}

extension OriginalSingularFieldRoot {
    /// Contract an exact linear-fractional image of the same retained ancestor.
    func rationalImageRefinedOnce<B: RationalAlgebraAdmitting>(maximumDepth: Int, forSeparation: Bool,
        usage: inout B) throws -> Self? {
        guard polynomial.degree == 1, case .parameter = admissionDomain,
            case .extended(let parent) = polynomial.context.source,
            case .parameter = parent.admissionDomain,
            case .extended(let numerator, let denominator) = polynomial.coefficients[0].storage,
            numerator.degree >= 0, numerator.degree <= 1,
            denominator.degree >= 0, denominator.degree <= 1,
            let leading = try polynomial.coefficients[1].rationalValue(usage: &usage),
            let n0 = try numerator.coefficients[0].rationalValue(usage: &usage),
            let d0 = try denominator.coefficients[0].rationalValue(usage: &usage) else { return nil }
        guard numerator.context === parent.polynomial.context, denominator.context === parent.polynomial.context else {
            throw exactScalarBackendFailure("An original scalar image has an unrelated ancestor field.")
        }
        guard !leading.isZero, !denominator.isZero else {
            throw exactScalarBackendFailure("An original scalar image lost its source denominator or leading coefficient.")
        }
        let n1: ExactRationalCoefficient, d1: ExactRationalCoefficient
        if numerator.degree == 1 {
            guard let value = try numerator.coefficients[1].rationalValue(usage: &usage) else { return nil }
            n1 = value
        } else { n1 = .zero }
        if denominator.degree == 1 {
            guard parent.polynomial.degree == 2,
                let value = try denominator.coefficients[1].rationalValue(usage: &usage) else { return nil }
            d1 = value
        } else { d1 = .zero }
        let a = n1.negated, b = n0.negated
        let c = try d1.multiplied(by: leading, usage: &usage)
        let d = try d0.multiplied(by: leading, usage: &usage)
        let determinant = try a.multiplied(by: d, usage: &usage)
            .subtracting(b.multiplied(by: c, usage: &usage), usage: &usage)
        // Both guarded domains are parameter domains; forward the same caller ledger
        // without recursively nesting a generic admission adapter in Embedded Swift.
        var ancestor: ExactAlgebraicRealRoot
        if let retainedRationalImageAncestor { ancestor = retainedRationalImageAncestor }
        else {
            guard let issued = try parent.retainedRationalRoot ?? parent.rationalAuthority(usage: &usage) else { return nil }
            ancestor = try issued.retainingIsolation(.init(lower: parent.isolation.lower, upper: parent.isolation.upper,
                isRationalStation: parent.isolation.lower == parent.isolation.upper,
                isolationDepth: parent.isolation.depth, excludesLowerEndpoint: parent.isolation.excludesLower,
                excludesUpperEndpoint: parent.isolation.excludesUpper), usage: &usage)
        }
        let width = try isolation.upper.subtracting(isolation.lower, usage: &usage)
            .divided(by: .natural(2, usage: &usage), usage: &usage)
        while true {
            try usage.consumeExactWork(1)
            let lowerDenominator = try c.multiplied(by: ancestor.isolation.lower, usage: &usage).adding(d, usage: &usage)
            let upperDenominator = try c.multiplied(by: ancestor.isolation.upper, usage: &usage).adding(d, usage: &usage)
            // A linear denominator has a nonzero sign throughout the bracket only
            // when both endpoints have that same strict sign. A pole requires
            // contraction of this same ancestor, even at an excluded endpoint.
            if !lowerDenominator.isZero, !upperDenominator.isZero,
                lowerDenominator.isPositive == upperDenominator.isPositive {
                let first = try a.multiplied(by: ancestor.isolation.lower, usage: &usage).adding(b, usage: &usage)
                    .divided(by: lowerDenominator, usage: &usage)
                let second = try a.multiplied(by: ancestor.isolation.upper, usage: &usage).adding(b, usage: &usage)
                    .divided(by: upperDenominator, usage: &usage)
                let imageLower = determinant.isNegative ? second : first
                let imageUpper = determinant.isNegative ? first : second
                let imageExcludesLower = !determinant.isZero && (determinant.isNegative
                    ? ancestor.isolation.excludesUpperEndpoint : ancestor.isolation.excludesLowerEndpoint)
                let imageExcludesUpper = !determinant.isZero && (determinant.isNegative
                    ? ancestor.isolation.excludesLowerEndpoint : ancestor.isolation.excludesUpperEndpoint)
                let lowerDifference = try imageLower.subtracting(isolation.lower, usage: &usage)
                let upperDifference = try imageUpper.subtracting(isolation.upper, usage: &usage)
                let lower = lowerDifference.isNegative ? isolation.lower : imageLower
                let upper = upperDifference.isPositive ? isolation.upper : imageUpper
                let excludesLower = lowerDifference.isZero ? isolation.excludesLower || imageExcludesLower
                    : lowerDifference.isNegative ? isolation.excludesLower : imageExcludesLower
                let excludesUpper = upperDifference.isZero ? isolation.excludesUpper || imageExcludesUpper
                    : upperDifference.isPositive ? isolation.excludesUpper : imageExcludesUpper
                let attainedWidth = try upper.subtracting(lower, usage: &usage)
                guard !attainedWidth.isNegative else {
                    throw exactScalarBackendFailure("Original scalar image contradicts its retained bracket.")
                }
                if !(try attainedWidth.subtracting(width, usage: &usage)).isPositive {
                    let depth = max(isolation.depth, ancestor.isolation.isolationDepth)
                    try admissionDomain.visit(depth, usage: &usage)
                    let sequence = try OriginalSingularFieldSturm(polynomial, maximumDepth: maximumDepth, usage: &usage)
                    guard try sequence.count(lower: lower, upper: upper, excludesLower: excludesLower,
                        excludesUpper: excludesUpper, maximumDepth: maximumDepth, usage: &usage) == 1 else {
                        throw exactScalarBackendFailure("Original scalar image lost unique-root authority.")
                    }
                    try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
                    return retainingIsolation(.init(lower: lower, upper: upper, excludesLower: excludesLower,
                        excludesUpper: excludesUpper, depth: depth), imageAncestor: ancestor)
                }
            }
            guard ancestor.isolation.lower != ancestor.isolation.upper else {
                throw exactScalarBackendFailure("Original scalar image has a zero source denominator.")
            }
            let ancestorWidth = try ancestor.isolation.upper.subtracting(ancestor.isolation.lower, usage: &usage)
                .divided(by: .natural(2, usage: &usage), usage: &usage)
            ancestor = try forSeparation
                ? ancestor.refinedForSeparation(maximumWidth: ancestorWidth, maximumDepth: maximumDepth, usage: &usage)
                : ancestor.refined(maximumWidth: ancestorWidth, maximumDepth: maximumDepth, usage: &usage)
        }
    }
}
