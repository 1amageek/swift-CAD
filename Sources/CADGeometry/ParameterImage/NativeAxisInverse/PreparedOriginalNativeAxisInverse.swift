import CADCore

/// Complete original native axis law and its strict monotone inverse.
package struct PreparedOriginalNativeAxisInverse: Sendable {
    package let source: BSplineCurve2D
    package let alongU: Bool
    package let orientation: Int
    package let fixedCoordinate: ExactRationalCoefficient
    package let nativeLower: ExactRationalCoefficient
    package let nativeWidth: ExactRationalCoefficient
    private let owners: [Owner]

    private struct Owner: Sendable {
        let spanIndex: Int
        let lower: ExactRationalCoefficient
        let upper: ExactRationalCoefficient
        let axis: ExactBivariatePolynomial
        let weight: ExactBivariatePolynomial
        let firstCoordinate: ExactRationalCoefficient
        let lastCoordinate: ExactRationalCoefficient
    }

    package struct Station: Sendable {
        package let originalSource: BSplineCurve2D
        package let alongU: Bool
        package let originalTarget: ExactRationalCoefficient
        package let originalAxisEquation: ExactBivariatePolynomial
        package let adjacentAxisEquation: ExactBivariatePolynomial?
        package let originalRoot: ExactAlgebraicRealRoot
        package let firstNativeSpanIndex: Int
        package let adjacentNativeSpanIndex: Int?
        package let nativeLower: ExactRationalCoefficient
        package let nativeWidth: ExactRationalCoefficient
        package let normalizedLower: ExactRationalCoefficient
        package let normalizedUpper: ExactRationalCoefficient
        package let normalizedEnclosure: ScalarInterval
        package let orientation: Int
        package let fixedCoordinate: ExactRationalCoefficient
    }

    package init<B: ExactScalarAdmission & ~Copyable>(source: BSplineCurve2D, alongU: Bool,
        tolerance: ModelingTolerance, remainingSourceDepth: Int, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int,
        usage: inout B) throws {
        guard remainingSourceDepth >= 0, maximumSpanCount > 0,
              maximumSubdivisionDepth >= 0, (0...32).contains(maximumAlgebraicDepth) else {
            throw rationalAlgebraFailure("Original native inverse requires an explicit valid caller policy.")
        }
        try source.validate(tolerance: tolerance, using: &usage)
        let lower = try ExactRationalCoefficient.originalDouble(source.knots[source.degree], usage: &usage)
        let upper = try ExactRationalCoefficient.originalDouble(source.knots[source.controlPoints.count], usage: &usage)
        let width = try upper.subtracting(lower, usage: &usage)
        guard width.isPositive else { throw rationalAlgebraFailure("Original native inverse domain is not increasing.") }
        var prepared: [Owner] = []
        var constant: ExactRationalCoefficient?
        var direction = 0
        var previousCoordinate: ExactRationalCoefficient?
        for span in source.degree..<source.controlPoints.count {
            try CurrentTaskCancellationChecker().checkCancellation()
            try usage.consumeWork(1)
            if source.knots[span] == source.knots[span + 1] { continue }
            guard prepared.count < maximumSpanCount else {
                throw GeometryConversionError.resourceLimitExceeded("Original native inverse exhausted caller span count.")
            }
            let basis = try OriginalRationalBSplineBasis.powerPolynomials(knots: source.knots,
                degree: source.degree, span: span, alongU: true, translation: 0, usage: &usage)
            var axis = ExactBivariatePolynomial.zero
            var other = ExactBivariatePolynomial.zero
            var weight = ExactBivariatePolynomial.zero
            for index in (span - source.degree)...span {
                try usage.consumeWork(1)
                guard let originalBasis = basis[index] else {
                    throw rationalAlgebraFailure("Original native inverse basis omitted an owning control.")
                }
                let w = try ExactRationalCoefficient.originalDouble(source.weights[index], usage: &usage)
                let point = source.controlPoints[index]
                let selected = try ExactRationalCoefficient.originalDouble(alongU ? point.x : point.y, usage: &usage)
                let remaining = try ExactRationalCoefficient.originalDouble(alongU ? point.y : point.x, usage: &usage)
                axis = try axis.adding(originalBasis.scaled(by: selected.multiplied(by: w, usage: &usage), usage: &usage), usage: &usage)
                other = try other.adding(originalBasis.scaled(by: remaining.multiplied(by: w, usage: &usage), usage: &usage), usage: &usage)
                weight = try weight.adding(originalBasis.scaled(by: w, usage: &usage), usage: &usage)
            }
            let a = try ExactRationalCoefficient.originalDouble(source.knots[span], usage: &usage)
            let b = try ExactRationalCoefficient.originalDouble(source.knots[span + 1], usage: &usage)
            let wa = try weight.evaluated(atU: a, v: .zero, usage: &usage)
            let wb = try weight.evaluated(atU: b, v: .zero, usage: &usage)
            guard wa.isPositive, wb.isPositive else {
                throw rationalAlgebraFailure("Original native inverse lost positive homogeneous denominator.")
            }
            let otherAtStart = try other.evaluated(atU: a, v: .zero, usage: &usage).divided(by: wa, usage: &usage)
            let fixed = constant ?? otherAtStart
            guard try other.subtracting(weight.scaled(by: fixed, usage: &usage), usage: &usage).isZero else {
                throw rationalAlgebraFailure("Original native pcurve is not wholly axis aligned.")
            }
            let numerator = try axis.differentiated(alongU: true, usage: &usage)
                .multiplied(by: weight, usage: &usage)
                .subtracting(axis.multiplied(by: weight.differentiated(alongU: true, usage: &usage), usage: &usage), usage: &usage)
            let sign = try Self.monotoneSign(numerator, lower: a, upper: b,
                maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &usage)
            guard direction == 0 || direction == sign else {
                throw rationalAlgebraFailure("Original native axis orientation changes across owners.")
            }
            let first = try axis.evaluated(atU: a, v: .zero, usage: &usage).divided(by: wa, usage: &usage)
            let last = try axis.evaluated(atU: b, v: .zero, usage: &usage).divided(by: wb, usage: &usage)
            let displacement = try last.subtracting(first, usage: &usage)
            guard (sign > 0 ? displacement.isPositive : displacement.isNegative),
                  previousCoordinate.map({ $0 == first }) ?? true else {
                throw rationalAlgebraFailure("Original native monotone owner contradicts its exact C0 join or orientation.")
            }
            try RationalAlgebraStorage.retain(1, of: Owner.self, usage: &usage)
            prepared.append(Owner(spanIndex: span, lower: a, upper: b, axis: axis,
                weight: weight, firstCoordinate: first, lastCoordinate: last))
            direction = sign; constant = fixed; previousCoordinate = last
        }
        guard let constant, !prepared.isEmpty else {
            throw rationalAlgebraFailure("Original native inverse has no nonconstant positive owner.")
        }
        self.source = source; self.alongU = alongU; orientation = direction
        fixedCoordinate = constant; nativeLower = lower; nativeWidth = width
        owners = prepared
    }

    /// The target is an original native UV coefficient, not a rounded source fraction.
    package func station<B: ExactScalarAdmission & ~Copyable>(at target: ExactRationalCoefficient,
        maximumNormalizedParameterWidth: Double, maximumAlgebraicDepth: Int,
        usage: inout B) throws -> Station? {
        guard maximumNormalizedParameterWidth.isFinite, maximumNormalizedParameterWidth > 0,
              (0...32).contains(maximumAlgebraicDepth) else {
            throw rationalAlgebraFailure("Original native inverse query cannot inherit a proof beyond its selected algebra policy.")
        }
        let normalizedWidth = try ExactRationalCoefficient.originalDouble(maximumNormalizedParameterWidth, usage: &usage)
        let nativeLocalizationWidth = try normalizedWidth.multiplied(by: nativeWidth, usage: &usage)
        var result: ExactAlgebraicRealRoot?
        var originalEquation: ExactBivariatePolynomial?
        var adjacentEquation: ExactBivariatePolynomial?
        var firstSpan: Int?
        var adjacentSpan: Int?
        var sharedStation: ExactRationalCoefficient?
        for owner in owners {
            try CurrentTaskCancellationChecker().checkCancellation()
            try usage.consumeWork(1)
            let a = try target.subtracting(owner.firstCoordinate, usage: &usage)
            let b = try owner.lastCoordinate.subtracting(target, usage: &usage)
            if orientation > 0 ? (a.isNegative || b.isNegative) : (a.isPositive || b.isPositive) { continue }
            let equation = try owner.axis.subtracting(owner.weight.scaled(by: target, usage: &usage), usage: &usage)
            guard !equation.isZero else {
                throw rationalAlgebraFailure("Strict original native inverse unexpectedly has a constant target owner.")
            }
            let roots = try ExactUnivariateRootIsolator().isolate(equation,
                lower: owner.lower, upper: owner.upper, maximumDepth: maximumAlgebraicDepth, usage: &usage)
            guard roots.count == 1 else {
                throw rationalAlgebraFailure("Complete original native inverse root count contradicts strict monotonicity.")
            }
            let root = try ExactAlgebraicRealRoot(polynomial: equation, isolation: roots[0], usage: &usage)
                .refined(maximumWidth: nativeLocalizationWidth, maximumDepth: maximumAlgebraicDepth, usage: &usage)
            if result != nil {
                guard let sharedStation, adjacentSpan == nil,
                      root.isolation.isRationalStation, root.isolation.lower == sharedStation,
                      owner.lower == sharedStation else {
                    throw rationalAlgebraFailure("Distinct original inverse roots cannot be merged by proximity.")
                }
                adjacentSpan = owner.spanIndex
                adjacentEquation = equation
            } else {
                result = root; firstSpan = owner.spanIndex
                originalEquation = equation
                if root.isolation.isRationalStation, root.isolation.lower == owner.upper {
                    sharedStation = owner.upper
                }
            }
        }
        guard let root = result, let firstSpan, let originalEquation else { return nil }
        let a = try root.isolation.lower.subtracting(nativeLower, usage: &usage).divided(by: nativeWidth, usage: &usage)
        let b = try root.isolation.upper.subtracting(nativeLower, usage: &usage).divided(by: nativeWidth, usage: &usage)
        let low = try a.outwardInterval(usage: &usage), high = try b.outwardInterval(usage: &usage)
        guard !a.isNegative, !(try ExactRationalCoefficient.one.subtracting(b, usage: &usage)).isNegative else {
            throw rationalAlgebraFailure("Original normalized inverse station escaped its source domain.")
        }
        try RationalAlgebraStorage.retain(1, of: Station.self, usage: &usage)
        return Station(originalSource: source, alongU: alongU, originalTarget: target,
            originalAxisEquation: originalEquation, adjacentAxisEquation: adjacentEquation,
            originalRoot: root, firstNativeSpanIndex: firstSpan,
            adjacentNativeSpanIndex: adjacentSpan, nativeLower: nativeLower, nativeWidth: nativeWidth,
            normalizedLower: a, normalizedUpper: b,
            normalizedEnclosure: try ScalarInterval(lower: low.lower, upper: high.upper),
            orientation: orientation, fixedCoordinate: fixedCoordinate)
    }

    private static func monotoneSign<B: ExactScalarAdmission & ~Copyable>(_ numerator: ExactBivariatePolynomial,
        lower: ExactRationalCoefficient, upper: ExactRationalCoefficient,
        maximumAlgebraicDepth: Int, usage: inout B) throws -> Int {
        guard !numerator.isZero else {
            throw rationalAlgebraFailure("An original constant plateau has no unique native axis inverse.")
        }
        let gcd = ExactBivariateGCD()
        var repeated = try gcd.univariateGCD(numerator,
            numerator.differentiated(alongU: true, usage: &usage), usage: &usage)
        var residual = try numerator.dividedExactly(by: repeated, usage: &usage)
        var odd = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        var multiplicity = 1
        while residual.uDegree > 0 {
            try usage.consumeWork(1)
            let common = try gcd.univariateGCD(residual, repeated, usage: &usage)
            let factor = try residual.dividedExactly(by: common, usage: &usage)
            if multiplicity & 1 == 1 { odd = try odd.multiplied(by: factor, usage: &usage) }
            residual = common
            repeated = try repeated.dividedExactly(by: common, usage: &usage)
            multiplicity = try rationalAlgebraCount(multiplicity, 1)
            guard multiplicity <= (try rationalAlgebraCount(numerator.uDegree, 1)) else {
                throw rationalAlgebraFailure("Original derivative multiplicity decomposition failed to decrease.")
            }
        }
        if odd.uDegree > 0 {
            let roots = try ExactUnivariateRootIsolator().isolate(odd, lower: lower, upper: upper,
                maximumDepth: maximumAlgebraicDepth, usage: &usage)
            for root in roots {
                try usage.consumeWork(1)
                guard root.isRationalStation, root.lower == lower || root.lower == upper else {
                    throw rationalAlgebraFailure("Original native axis derivative changes sign inside an owner.")
                }
            }
        }
        // A nonzero degree-D polynomial cannot vanish at D+1 distinct interior
        // rational stations. Completeness comes from the odd-root proof above;
        // this finite witness selects its sign, never sampled absence authority.
        let count = try rationalAlgebraCount(numerator.uDegree, 1)
        let divisor = try ExactRationalCoefficient.natural(rationalAlgebraCount(count, 1), usage: &usage)
        let width = try upper.subtracting(lower, usage: &usage)
        for index in 1...count {
            try usage.consumeWork(1)
            let fraction = try ExactRationalCoefficient.natural(index, usage: &usage).divided(by: divisor, usage: &usage)
            let station = try lower.adding(width.multiplied(by: fraction, usage: &usage), usage: &usage)
            let value = try numerator.evaluated(atU: station, v: .zero, usage: &usage)
            if !value.isZero { return value.isPositive ? 1 : -1 }
        }
        throw rationalAlgebraFailure("Original derivative sign witness contradicts its nonzero polynomial degree.")
    }
}
