import CADCore

/// A unique real source root with exact polynomial and admitted isolating interval.
public struct ExactAlgebraicRealRoot: Sendable {
    public enum Sign: Sendable { case negative, zero, positive }
    public let polynomial: ExactBivariatePolynomial
    public let isolation: ExactUnivariateRootIsolator.Root
    private let sequence: ExactUnivariateSturmSequence

    public init<B: RationalAlgebraAdmitting>(polynomial: ExactBivariatePolynomial,
        isolation: ExactUnivariateRootIsolator.Root, usage: inout B) throws {
        sequence = try ExactUnivariateSturmSequence(polynomial, usage: &usage)
        guard try sequence.count(lower: isolation.lower, upper: isolation.upper,
            excludesLower: isolation.excludesLowerEndpoint,
            excludesUpper: isolation.excludesUpperEndpoint, usage: &usage) == 1 else {
            throw rationalAlgebraFailure("Algebraic source root does not have exact unique-root authority.")
        }
        guard isolation.isolationDepth >= 0 else {
            throw rationalAlgebraFailure("Original root isolation depth must be nonnegative.")
        }
        self.polynomial = sequence.source; self.isolation = isolation
    }

    private init(polynomial: ExactBivariatePolynomial, isolation: ExactUnivariateRootIsolator.Root,
                 sequence: ExactUnivariateSturmSequence) {
        self.polynomial = polynomial; self.isolation = isolation; self.sequence = sequence
    }

    /// Carries causal pair depth without changing the certified original root.
    func retainingDepth(_ depth: Int) throws -> Self {
        guard depth >= isolation.isolationDepth else {
            throw rationalAlgebraFailure("Original root depth cannot move backwards.")
        }
        let station = ExactUnivariateRootIsolator.Root(lower: isolation.lower, upper: isolation.upper,
            isRationalStation: isolation.isRationalStation, isolationDepth: depth,
            excludesLowerEndpoint: isolation.excludesLowerEndpoint,
            excludesUpperEndpoint: isolation.excludesUpperEndpoint)
        return Self(polynomial: polynomial, isolation: station, sequence: sequence)
    }

    public func refined<B: RationalAlgebraAdmitting>(maximumWidth: ExactRationalCoefficient,
        maximumDepth: Int, usage: inout B) throws -> Self {
        guard maximumWidth.isPositive, maximumDepth >= isolation.isolationDepth else {
            throw rationalAlgebraFailure("Exact algebraic refinement needs positive width and caller depth.")
        }
        var lower = isolation.lower, upper = isolation.upper
        var excludesLower = isolation.excludesLowerEndpoint, excludesUpper = isolation.excludesUpperEndpoint
        var depth = isolation.isolationDepth
        if !excludesLower, try polynomial.evaluated(atU: lower, v: .zero, usage: &usage).isZero {
            upper = lower; excludesUpper = false
        } else if !excludesUpper, try polynomial.evaluated(atU: upper, v: .zero, usage: &usage).isZero {
            lower = upper; excludesLower = false
        }
        if lower != upper, polynomial.uDegree == 1 {
            try usage.visitExactCell(depth: depth)
            let slope = polynomial.coefficients[try .init(u: 1, v: 0)] ?? .zero
            let constant = polynomial.coefficients[try .init(u: 0, v: 0)] ?? .zero
            guard !slope.isZero else { throw rationalAlgebraFailure("Original degree-one root lost its leading coefficient.") }
            let value = try constant.negated.divided(by: slope, usage: &usage)
            guard !(try value.subtracting(lower, usage: &usage)).isNegative,
                  !(try upper.subtracting(value, usage: &usage)).isNegative,
                  !(value == lower && excludesLower), !(value == upper && excludesUpper),
                  try polynomial.evaluated(atU: value, v: .zero, usage: &usage).isZero,
                  try sequence.count(lower: value, upper: value, excludesLower: false,
                    excludesUpper: false, usage: &usage) == 1 else {
                throw rationalAlgebraFailure("Exact linear root contradicts its retained original isolation.")
            }
            lower = value; upper = value; excludesLower = false; excludesUpper = false
        }
        if lower == upper {
            let station = ExactUnivariateRootIsolator.Root(lower: lower, upper: upper,
                isRationalStation: true, isolationDepth: depth,
                excludesLowerEndpoint: false, excludesUpperEndpoint: false)
            return Self(polynomial: polynomial, isolation: station, sequence: sequence)
        }
        let derivative = try polynomial.differentiated(alongU: true, usage: &usage)
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        while try upper.subtracting(lower, usage: &usage).subtracting(maximumWidth, usage: &usage).isPositive {
            try usage.visitExactCell(depth: depth)
            guard depth < maximumDepth else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                    message: "Original algebraic root refinement exhausted caller depth.")
            }
            let middle = try lower.adding(upper, usage: &usage).divided(by: two, usage: &usage)
            let middleValue = try polynomial.evaluated(atU: middle, v: .zero, usage: &usage)
            if middleValue.isZero {
                lower = middle; upper = middle; excludesLower = false; excludesUpper = false; depth += 1; break
            }
            let derivativeRange = try OriginalRationalPolynomialRange(original: derivative,
                lower: lower, upper: upper, usage: &usage)
            if derivativeRange.lower.isPositive || derivativeRange.upper.isNegative {
                let first = try middleValue.divided(by: derivativeRange.lower, usage: &usage)
                let last = try middleValue.divided(by: derivativeRange.upper, usage: &usage)
                let ascending = try last.subtracting(first, usage: &usage).isPositive
                let newtonLower = try middle.subtracting(ascending ? last : first, usage: &usage)
                let newtonUpper = try middle.subtracting(ascending ? first : last, usage: &usage)
                let nextLower = try newtonLower.subtracting(lower, usage: &usage).isPositive ? newtonLower : lower
                let nextUpper = try upper.subtracting(newtonUpper, usage: &usage).isPositive ? newtonUpper : upper
                let nextExcludesLower = nextLower == lower ? excludesLower : false
                let nextExcludesUpper = nextUpper == upper ? excludesUpper : false
                guard !(try nextUpper.subtracting(nextLower, usage: &usage)).isNegative,
                      nextLower != lower || nextUpper != upper,
                      try sequence.count(lower: nextLower, upper: nextUpper,
                        excludesLower: nextExcludesLower, excludesUpper: nextExcludesUpper,
                        usage: &usage) == 1 else {
                    throw rationalAlgebraFailure("Original rational interval Newton contraction contradicted unique-root authority.")
                }
                lower = nextLower; upper = nextUpper
                excludesLower = nextExcludesLower; excludesUpper = nextExcludesUpper
                depth += 1
                continue
            }
            let left = try sequence.count(lower: lower, upper: middle,
                excludesLower: excludesLower, excludesUpper: false, usage: &usage)
            if left == 1 { upper = middle; excludesUpper = false }
            else if left == 0 { lower = middle; excludesLower = true }
            else { throw rationalAlgebraFailure("Original algebraic root refinement lost unique source authority.") }
            depth += 1
        }
        let station = ExactUnivariateRootIsolator.Root(lower: lower, upper: upper,
            isRationalStation: lower == upper, isolationDepth: depth, excludesLowerEndpoint: excludesLower,
            excludesUpperEndpoint: excludesUpper)
        return Self(polynomial: polynomial, isolation: station, sequence: sequence)
    }

    public func sign<B: RationalAlgebraAdmitting>(of expression: ExactBivariatePolynomial,
        maximumDepth: Int, usage: inout B) throws -> Sign {
        guard expression.vDegree <= 0, maximumDepth >= isolation.isolationDepth else {
            throw rationalAlgebraFailure("Algebraic source sign needs a univariate expression and caller depth.")
        }
        if expression.isZero { return .zero }
        if expression.uDegree == 1 {
            try CurrentTaskCancellationChecker().checkCancellation(); try usage.visitExactCell(depth: isolation.isolationDepth)
            let constant = try expression.evaluated(atU: .zero, v: .zero, usage: &usage)
            let leading = try expression.evaluated(atU: .one, v: .zero, usage: &usage)
                .subtracting(constant, usage: &usage)
            guard !leading.isZero else { throw rationalAlgebraFailure("A linear expression lost its original leading coefficient.") }
            let station = try constant.negated.divided(by: leading, usage: &usage)
            let positive: Sign = leading.isPositive ? .positive : .negative
            let negative: Sign = leading.isPositive ? .negative : .positive
            let lowerOrder = try station.subtracting(isolation.lower, usage: &usage)
            let upperOrder = try station.subtracting(isolation.upper, usage: &usage)
            if lowerOrder.isNegative || lowerOrder.isZero && isolation.excludesLowerEndpoint { return positive }
            if upperOrder.isPositive || upperOrder.isZero && isolation.excludesUpperEndpoint { return negative }
            if try polynomial.evaluated(atU: station, v: .zero, usage: &usage).isZero { return .zero }
            let left = try sequence.count(lower: isolation.lower, upper: station,
                excludesLower: isolation.excludesLowerEndpoint, excludesUpper: false, usage: &usage)
            guard left == 0 || left == 1 else {
                throw rationalAlgebraFailure("Original linear sign contradicts its unique real-root authority.")
            }
            return left == 0 ? positive : negative
        }
        let gcd = try ExactBivariateGCD().univariateGCD(polynomial, expression, usage: &usage)
        if gcd.uDegree > 0 {
            let shared = try ExactUnivariateSturmSequence(gcd, usage: &usage)
            if try shared.count(lower: isolation.lower, upper: isolation.upper,
                excludesLower: isolation.excludesLowerEndpoint, excludesUpper: isolation.excludesUpperEndpoint,
                usage: &usage) == 1 { return .zero }
        }
        var retained = self
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        while true {
            let station = retained.isolation
            try CurrentTaskCancellationChecker().checkCancellation(); try usage.visitExactCell(depth: station.isolationDepth)
            let interval = try OriginalRationalPolynomialRange(original: expression,
                lower: station.lower, upper: station.upper, usage: &usage)
            if interval.lower.isPositive { return .positive }
            if interval.upper.isNegative { return .negative }
            if station.lower == station.upper {
                let value = try expression.evaluated(atU: station.lower, v: .zero, usage: &usage)
                return value.isZero ? .zero : value.isPositive ? .positive : .negative
            }
            guard station.isolationDepth < maximumDepth || polynomial.uDegree == 1 else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                    message: "Exact algebraic source sign exhausted caller refinement depth.")
            }
            let width = try station.upper.subtracting(station.lower, usage: &usage)
                .divided(by: two, usage: &usage)
            retained = try retained.refined(maximumWidth: width, maximumDepth: maximumDepth, usage: &usage)
        }
    }
}
