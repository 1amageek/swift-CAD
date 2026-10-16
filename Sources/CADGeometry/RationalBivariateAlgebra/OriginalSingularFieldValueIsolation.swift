import CADCore

/// Persistent exact value bounds and the depth actually used to prove them.
package struct OriginalSingularFieldValueIsolation: Sendable {
    package let original: OriginalSingularFieldElement
    package let lower: ExactRationalCoefficient
    package let upper: ExactRationalCoefficient
    package let sourceDepth: Int

    private static func exhausted() -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
            message: "Original scalar enclosure exhausted its retained causal caller depth.")
    }

    private static func compare<B: ExactScalarAdmission & ~Copyable>(_ value: OriginalSingularFieldElement,
        to candidate: ExactRationalCoefficient, depth: inout Int, maximumDepth: Int,
        usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        guard depth >= value.context.depth, depth <= maximumDepth else { throw exhausted() }
        let available = try rationalAlgebraCount(value.context.depth, maximumDepth - depth)
        return try usage.withProofScope(
            original: .init(value: value.context.depth, coefficient: 0),
            inherited: .init(value: depth, coefficient: 0),
            maximum: .init(value: maximumDepth, coefficient: Int.max)
        ) { usage in
            defer { depth = max(depth, usage.proofScopes.depth.value) }
            let other = try OriginalSingularFieldElement.constant(candidate, in: value.context,
                maximumDepth: available, usage: &usage)
            return try value.subtracting(other, maximumDepth: available, usage: &usage)
                .sign(maximumDepth: available, usage: &usage)
        }
    }

    package init<B: ExactScalarAdmission & ~Copyable>(original: OriginalSingularFieldElement,
        inheritedDepth: Int, maximumDepth: Int, usage: inout B) throws {
        var depth = max(inheritedDepth, original.context.depth)
        guard inheritedDepth >= 0, depth <= maximumDepth else { throw Self.exhausted() }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        if let rational = try original.rationalValue(usage: &usage) {
            self.original = original; lower = rational; upper = rational; sourceDepth = depth
            return
        }
        if case .zero = try Self.compare(original, to: .zero, depth: &depth,
            maximumDepth: maximumDepth, usage: &usage) {
            self.original = original; lower = .zero; upper = .zero; sourceDepth = depth
            return
        }
        var bound = ExactRationalCoefficient.one
        while true {
            try usage.consumeWork(1)
            let a = try Self.compare(original, to: bound.negated, depth: &depth,
                maximumDepth: maximumDepth, usage: &usage)
            let b = try Self.compare(original, to: bound, depth: &depth,
                maximumDepth: maximumDepth, usage: &usage)
            if case .zero = a {
                self.original = original; lower = bound.negated; upper = bound.negated; sourceDepth = depth
                return
            }
            if case .zero = b {
                self.original = original; lower = bound; upper = bound; sourceDepth = depth
                return
            }
            if case .positive = a, case .negative = b {
                self.original = original; lower = bound.negated; upper = bound; sourceDepth = depth
                return
            }
            bound = try bound.multiplied(by: .natural(2, usage: &usage), usage: &usage)
        }
    }

    /// Verifies a retained source enclosure before using it as a localization seed.
    package init<B: ExactScalarAdmission & ~Copyable>(original: OriginalSingularFieldElement,
        lower: ExactRationalCoefficient, upper: ExactRationalCoefficient,
        inheritedDepth: Int, maximumDepth: Int, usage: inout B) throws {
        var depth = max(inheritedDepth, original.context.depth)
        guard inheritedDepth >= 0, depth <= maximumDepth else { throw Self.exhausted() }
        guard !(try upper.subtracting(lower, usage: &usage)).isNegative else {
            throw rationalAlgebraFailure("Original scalar seed has reversed rational bounds.")
        }
        let lowerSign = try Self.compare(original, to: lower, depth: &depth,
            maximumDepth: maximumDepth, usage: &usage)
        let upperSign = try Self.compare(original, to: upper, depth: &depth,
            maximumDepth: maximumDepth, usage: &usage)
        guard lowerSign != .negative, upperSign != .positive else {
            throw rationalAlgebraFailure("Original scalar seed excludes its retained exact field value.")
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        self.original = original; sourceDepth = depth
        if let rational = try original.rationalValue(usage: &usage) {
            self.lower = rational; self.upper = rational
        } else { self.lower = lower; self.upper = upper }
    }

    package func refined<B: ExactScalarAdmission & ~Copyable>(maximumWidth: ExactRationalCoefficient,
        maximumDepth: Int, usage: inout B) throws -> Self {
        guard maximumWidth.isPositive, sourceDepth <= maximumDepth else { throw Self.exhausted() }
        var a = lower, b = upper, depth = sourceDepth
        while try b.subtracting(a, usage: &usage).subtracting(maximumWidth, usage: &usage).isPositive {
            guard depth < maximumDepth else { throw Self.exhausted() }
            depth = try rationalAlgebraCount(depth, 1); try usage.visitCell(axis: .value, depth: depth)
            let middle = try a.adding(b, usage: &usage).divided(by: .natural(2, usage: &usage), usage: &usage)
            switch try Self.compare(original, to: middle, depth: &depth, maximumDepth: maximumDepth, usage: &usage) {
            case .zero: a = middle; b = middle
            case .negative: b = middle
            case .positive: a = middle
            }
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        return Self(original: original, lower: a, upper: b, sourceDepth: depth)
    }

    /// Compares against a rational station while retaining all achieved causal depth.
    package func compared<B: ExactScalarAdmission & ~Copyable>(to station: ExactRationalCoefficient,
        maximumDepth: Int, usage: inout B) throws -> (sign: ExactAlgebraicRealRoot.Sign, isolation: Self) {
        var depth = sourceDepth
        let sign = try Self.compare(original, to: station, depth: &depth,
            maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        return (sign, Self(original: original, lower: lower, upper: upper, sourceDepth: depth))
    }

    /// Retains the same proven bounds after an upstream path consumed more depth.
    package func inheriting<B: ExactScalarAdmission & ~Copyable>(depth: Int, maximumDepth: Int,
        usage: inout B) throws -> Self {
        let inherited = max(sourceDepth, depth)
        guard depth >= 0, inherited <= maximumDepth else { throw Self.exhausted() }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        return Self(original: original, lower: lower, upper: upper, sourceDepth: inherited)
    }

    package func enclosure<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> OutwardScalarInterval {
        let a = try lower.outwardInterval(usage: &usage), b = try upper.outwardInterval(usage: &usage)
        return OutwardScalarInterval(lower: a.lower, upper: b.upper)
    }

    private init(original: OriginalSingularFieldElement, lower: ExactRationalCoefficient,
        upper: ExactRationalCoefficient, sourceDepth: Int) {
        self.original = original; self.lower = lower; self.upper = upper; self.sourceDepth = sourceDepth
    }
}
