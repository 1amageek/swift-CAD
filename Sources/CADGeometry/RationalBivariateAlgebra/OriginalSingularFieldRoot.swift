import CADCore

/// One original real root with its parent field, endpoint exclusions and causal depth.
package struct OriginalSingularFieldRoot: Sendable {
    package struct Isolation: Sendable {
        package let lower: ExactRationalCoefficient
        package let upper: ExactRationalCoefficient
        package let excludesLower: Bool
        package let excludesUpper: Bool
        package let depth: Int
    }
    package enum AdmissionDomain: Sendable {
        case parameter
        case coefficient(maximumDepth: Int)

        func limit(_ parameterLimit: Int) -> Int {
            switch self { case .parameter: parameterLimit; case .coefficient(let limit): limit }
        }
        func inheritedDepth(of context: OriginalSingularFieldContext) -> Int {
            switch self { case .parameter: context.depth; case .coefficient: context.coefficientDepth }
        }
        func visit<B: RationalAlgebraAdmitting>(_ depth: Int, usage: inout B) throws {
            switch self {
            case .parameter: try usage.visitExactCell(depth: depth)
            case .coefficient: try usage.visitCoefficientCell(depth: depth)
            }
        }
    }
    private struct Pending: Sendable {
        let interval: Isolation
        let count: Int
    }
    package let polynomial: OriginalSingularFieldPolynomial
    package let isolation: Isolation
    package let admissionDomain: AdmissionDomain

    package init(polynomial: OriginalSingularFieldPolynomial, isolation: Isolation,
        admissionDomain: AdmissionDomain = .parameter) {
        self.polynomial = polynomial; self.isolation = isolation; self.admissionDomain = admissionDomain
    }

    package func value<B: RationalAlgebraAdmitting>(maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        let maximumDepth = admissionDomain.limit(maximumDepth)
        guard isolation.depth <= maximumDepth else { throw rationalAlgebraFailure("Original scalar value exceeds its retained admission domain.") }
        try admissionDomain.visit(isolation.depth, usage: &usage)
        let context = try OriginalSingularFieldContext(root: self, usage: &usage)
        let zero = try OriginalSingularFieldElement.constant(.zero, in: polynomial.context, maximumDepth: maximumDepth, usage: &usage)
        let one = try OriginalSingularFieldElement.constant(.one, in: polynomial.context, maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldElement.self, usage: &usage)
        let numerator = try OriginalSingularFieldPolynomial(context: polynomial.context, coefficients: [zero, one],
            maximumDepth: maximumDepth, usage: &usage)
        let denominator = try OriginalSingularFieldPolynomial(context: polynomial.context, coefficients: [one],
            maximumDepth: maximumDepth, usage: &usage)
        return OriginalSingularFieldElement(context: context, storage: .extended(numerator, denominator))
    }

    package func sign<B: RationalAlgebraAdmitting>(of expression: OriginalSingularFieldPolynomial,
        maximumDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        let maximumDepth = admissionDomain.limit(maximumDepth)
        guard isolation.depth <= maximumDepth else { throw rationalAlgebraFailure("Original scalar sign exceeds retained admission depth.") }
        try admissionDomain.visit(isolation.depth, usage: &usage)
        guard polynomial.context === expression.context else { throw rationalAlgebraFailure("Original tangent root sign has an unrelated parent field.") }
        if expression.isZero { return .zero }
        if expression.degree == 0 {
            return try expression.coefficients[0].sign(maximumDepth: maximumDepth, usage: &usage)
        }
        if expression.degree == 1 {
            return try linearSign(expression, maximumDepth: maximumDepth, usage: &usage)
        }
        let common = try OriginalSingularFieldPolynomial.gcd(polynomial, expression, maximumDepth: maximumDepth, usage: &usage)
        if common.degree > 0 {
            let sequence = try OriginalSingularFieldSturm(common, maximumDepth: maximumDepth, usage: &usage)
            if try sequence.count(lower: isolation.lower, upper: isolation.upper,
                excludesLower: isolation.excludesLower, excludesUpper: isolation.excludesUpper,
                maximumDepth: maximumDepth, usage: &usage) == 1 { return .zero }
        }
        let roots = try OriginalSingularFieldSturm(expression, maximumDepth: maximumDepth, usage: &usage)
        var retained = self
        while true {
            try usage.consumeExactWork(1)
            let first = try roots.sign(expression, at: retained.isolation.lower, maximumDepth: maximumDepth, usage: &usage)
            let second = try roots.sign(expression, at: retained.isolation.upper, maximumDepth: maximumDepth, usage: &usage)
            let noZero = try roots.count(lower: retained.isolation.lower, upper: retained.isolation.upper,
                excludesLower: false, excludesUpper: false, maximumDepth: maximumDepth, usage: &usage) == 0
            if noZero {
                switch (first, second) { case (.positive, .positive): return .positive
                case (.negative, .negative): return .negative
                default: throw rationalAlgebraFailure("Original tangent root sign contradicts complete no-zero coverage.") }
            }
            retained = try retained.refinedOnce(maximumDepth: maximumDepth, usage: &usage)
        }
    }

    private func linearSign<B: RationalAlgebraAdmitting>(_ expression: OriginalSingularFieldPolynomial,
        maximumDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        let leading = expression.coefficients[1]
        let orientation = try leading.sign(maximumDepth: maximumDepth, usage: &usage)
        guard orientation != .zero else {
            throw rationalAlgebraFailure("A retained linear root expression cannot have a zero leading coefficient.")
        }
        let zero = try expression.coefficients[0].negated(maximumDepth: maximumDepth, usage: &usage)
            .divided(by: leading, maximumDepth: maximumDepth, usage: &usage)
        let reversed: ExactAlgebraicRealRoot.Sign = orientation == .positive ? .negative : .positive
        let lower = try OriginalSingularFieldElement.constant(isolation.lower,
            in: polynomial.context, maximumDepth: maximumDepth, usage: &usage)
        let upper = try OriginalSingularFieldElement.constant(isolation.upper,
            in: polynomial.context, maximumDepth: maximumDepth, usage: &usage)
        let below = try zero.subtracting(lower, maximumDepth: maximumDepth, usage: &usage)
            .sign(maximumDepth: maximumDepth, usage: &usage)
        let above = try zero.subtracting(upper, maximumDepth: maximumDepth, usage: &usage)
            .sign(maximumDepth: maximumDepth, usage: &usage)
        if below == .negative || below == .zero && isolation.excludesLower { return orientation }
        if above == .positive || above == .zero && isolation.excludesUpper { return reversed }
        if try polynomial.evaluated(at: zero, maximumDepth: maximumDepth, usage: &usage)
            .sign(maximumDepth: maximumDepth, usage: &usage) == .zero { return .zero }
        let sequence = try OriginalSingularFieldSturm(polynomial, maximumDepth: maximumDepth, usage: &usage)
        var left = try sequence.variations(at: isolation.lower, maximumDepth: maximumDepth, usage: &usage)
            - sequence.variations(at: zero, maximumDepth: maximumDepth, usage: &usage)
        if !isolation.excludesLower,
            try sequence.sign(sequence.source, at: isolation.lower, maximumDepth: maximumDepth, usage: &usage) == .zero {
            left += 1
        }
        guard left == 0 || left == 1 else {
            throw rationalAlgebraFailure("Original linear sign contradicts its unique real-root count.")
        }
        return left == 0 ? orientation : reversed
    }

    package func refinedOnce<B: RationalAlgebraAdmitting>(maximumDepth: Int, usage: inout B) throws -> Self {
        let maximumDepth = admissionDomain.limit(maximumDepth)
        let bounds = isolation
        if try bounds.upper.subtracting(bounds.lower, usage: &usage).isZero { return self }
        guard bounds.depth <= maximumDepth else {
            throw rationalAlgebraFailure("Original field scalar refinement exceeds its retained admission domain.")
        }
        if let rational = try rationalRefinedOnce(maximumDepth: maximumDepth, usage: &usage) { return rational }
        guard bounds.depth < maximumDepth else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                message: "Original singular tangent refinement exhausted inherited caller depth.")
        }
        let depth = try rationalAlgebraCount(bounds.depth, 1)
        try admissionDomain.visit(depth, usage: &usage)
        let midpoint = try bounds.lower.adding(bounds.upper, usage: &usage).divided(by: .natural(2, usage: &usage), usage: &usage)
        let sequence = try OriginalSingularFieldSturm(polynomial, maximumDepth: maximumDepth, usage: &usage)
        if case .zero = try sequence.sign(polynomial, at: midpoint, maximumDepth: maximumDepth, usage: &usage) {
            return Self(polynomial: polynomial, isolation: .init(lower: midpoint, upper: midpoint,
                excludesLower: false, excludesUpper: false, depth: depth), admissionDomain: admissionDomain)
        }
        let left = try sequence.count(lower: bounds.lower, upper: midpoint, excludesLower: bounds.excludesLower,
            excludesUpper: false, maximumDepth: maximumDepth, usage: &usage)
        let right = try sequence.count(lower: midpoint, upper: bounds.upper, excludesLower: true,
            excludesUpper: bounds.excludesUpper, maximumDepth: maximumDepth, usage: &usage)
        guard left + right == 1 else { throw rationalAlgebraFailure("Original tangent refinement lost unique-root coverage.") }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        if left == 1 { return Self(polynomial: polynomial, isolation: .init(lower: bounds.lower, upper: midpoint,
            excludesLower: bounds.excludesLower, excludesUpper: false, depth: depth), admissionDomain: admissionDomain) }
        return Self(polynomial: polynomial, isolation: .init(lower: midpoint, upper: bounds.upper,
            excludesLower: true, excludesUpper: bounds.excludesUpper, depth: depth), admissionDomain: admissionDomain)
    }

    package func refined<B: RationalAlgebraAdmitting>(maximumWidth: ExactRationalCoefficient,
        maximumDepth: Int, usage: inout B) throws -> Self {
        let maximumDepth = admissionDomain.limit(maximumDepth)
        guard maximumWidth.isPositive, maximumDepth >= isolation.depth else {
            throw rationalAlgebraFailure("Original field root refinement needs positive width and inherited caller depth.")
        }
        var retained = self
        while try retained.isolation.upper.subtracting(retained.isolation.lower, usage: &usage)
            .subtracting(maximumWidth, usage: &usage).isPositive {
            retained = try retained.refinedOnce(maximumDepth: maximumDepth, usage: &usage)
        }
        return retained
    }

    package static func allRealRoots<B: RationalAlgebraAdmitting>(_ original: OriginalSingularFieldPolynomial,
        inheritedDepth: Int, maximumDepth: Int, admissionDomain: AdmissionDomain = .parameter,
        usage: inout B) throws -> [Self] {
        let maximumDepth = admissionDomain.limit(maximumDepth)
        guard !original.isZero else { throw rationalAlgebraFailure("Original tangent polynomial is identically zero.") }
        if original.degree == 0 { return [] }
        let sequence = try OriginalSingularFieldSturm(original, maximumDepth: maximumDepth, usage: &usage)
        let source = sequence.source
        guard let lead = source.coefficients.last else { throw rationalAlgebraFailure("Original tangent polynomial lost its leading coefficient.") }
        var bound = ExactRationalCoefficient.one
        while true {
            try usage.consumeExactWork(1)
            bound = try bound.multiplied(by: .natural(2, usage: &usage), usage: &usage)
            let margin = try OriginalSingularFieldElement.constant(bound.subtracting(.one, usage: &usage),
                in: source.context, maximumDepth: maximumDepth, usage: &usage)
            var admitted = true
            for coefficient in source.coefficients.dropLast() {
                let ratio = try coefficient.divided(by: lead, maximumDepth: maximumDepth, usage: &usage)
                if case .positive = try margin.subtracting(ratio, maximumDepth: maximumDepth, usage: &usage)
                    .sign(maximumDepth: maximumDepth, usage: &usage) {} else { admitted = false; break }
                if case .positive = try margin.adding(ratio, maximumDepth: maximumDepth, usage: &usage)
                    .sign(maximumDepth: maximumDepth, usage: &usage) {} else { admitted = false; break }
            }
            if admitted { break }
        }
        let parentDepth = max(admissionDomain.inheritedDepth(of: source.context), inheritedDepth)
        guard parentDepth <= maximumDepth else { throw rationalAlgebraFailure("Original tangent field inherited an inadmissible source depth.") }
        let lower = bound.negated, upper = bound
        let count = try sequence.count(lower: lower, upper: upper, excludesLower: true,
            excludesUpper: true, maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Pending.self, usage: &usage)
        var pending = [Pending(interval: .init(lower: lower, upper: upper,
            excludesLower: true, excludesUpper: true, depth: parentDepth), count: count)]
        var roots: [Self] = []
        while let cell = pending.popLast() {
            try admissionDomain.visit(cell.interval.depth, usage: &usage)
            if cell.count == 0 { continue }
            if cell.count == 1 {
                try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage); roots.append(Self(polynomial: source, isolation: cell.interval, admissionDomain: admissionDomain)); continue
            }
            guard cell.interval.depth < maximumDepth else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                    message: "Complete original tangent root isolation exhausted caller depth.")
            }
            let midpoint = try cell.interval.lower.adding(cell.interval.upper, usage: &usage)
                .divided(by: .natural(2, usage: &usage), usage: &usage)
            let left = try sequence.count(lower: cell.interval.lower, upper: midpoint,
                excludesLower: cell.interval.excludesLower, excludesUpper: false, maximumDepth: maximumDepth, usage: &usage)
            let right = try sequence.count(lower: midpoint, upper: cell.interval.upper,
                excludesLower: true, excludesUpper: cell.interval.excludesUpper, maximumDepth: maximumDepth, usage: &usage)
            guard left + right == cell.count else { throw rationalAlgebraFailure("Original tangent root partition lost coverage.") }
            try RationalAlgebraStorage.retain(2, of: Pending.self, usage: &usage)
            let depth = try rationalAlgebraCount(cell.interval.depth, 1)
            pending.append(Pending(interval: .init(lower: midpoint, upper: cell.interval.upper,
                excludesLower: true, excludesUpper: cell.interval.excludesUpper, depth: depth), count: right))
            pending.append(Pending(interval: .init(lower: cell.interval.lower, upper: midpoint,
                excludesLower: cell.interval.excludesLower, excludesUpper: false, depth: depth), count: left))
        }
        return roots
    }
}
