/// Operations in one explicit retained real algebraic domain.
public struct OriginalExactScalarDomain: ExactScalarArithmetic, ExactScalarOrdering, ExactScalarImporting {
    public typealias Value = OriginalExactScalar
    public typealias Source = OriginalExactScalar
    let context: OriginalSingularFieldContext
    public let maximumValueDepth: Int
    public let maximumCoefficientDepth: Int
    var originalDepth: ExactScalarDepth {
        .init(uncheckedValue: context.depth, coefficient: context.coefficientDepth)
    }

    public init<A: ExactScalarAdmission & ~Copyable>(maximumValueDepth: Int,
        maximumCoefficientDepth: Int, using admission: inout A) throws(ExactScalarFailure) {
        try admission.checkpoint()
        try Self.validateLimits(maximumValueDepth, maximumCoefficientDepth)
        let result = try ExactScalarNumericAccess.withAdmission(&admission) { usage in
            try OriginalSingularFieldContext(usage: &usage)
        }
        context = result.value; self.maximumValueDepth = maximumValueDepth
        self.maximumCoefficientDepth = maximumCoefficientDepth
    }

    /// Binds an already-certified original rational root; it performs no new search.
    public init<A: ExactScalarAdmission & ~Copyable>(root: ExactAlgebraicRealRoot,
        axis: ExactScalarRootAxis, maximumValueDepth: Int, maximumCoefficientDepth: Int,
        using admission: inout A) throws(ExactScalarFailure) {
        try admission.checkpoint()
        try Self.validateLimits(maximumValueDepth, maximumCoefficientDepth)
        let depth = ExactScalarDepth(uncheckedValue: axis == .value ? root.isolation.isolationDepth : 0,
            coefficient: axis == .coefficient ? root.isolation.isolationDepth : 0)
        try Self.validateDepth(depth, valueLimit: maximumValueDepth, coefficientLimit: maximumCoefficientDepth)
        let result = try ExactScalarNumericAccess.withAdmission(&admission, inherited: depth) { usage in
            let parent = try OriginalSingularFieldContext(usage: &usage)
            let count = try exactScalarCount(root.polynomial.uDegree, 1)
            guard count > 1, root.polynomial.vDegree <= 0 else { throw ExactScalarFailure.invalidEvidence }
            try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
            var coefficients: [OriginalSingularFieldElement] = []; coefficients.reserveCapacity(count)
            for index in 0..<count {
                try usage.consumeExactWork(1)
                let coefficient = root.polynomial.coefficients[try .init(u: index, v: 0)] ?? .zero
                coefficients.append(try .constant(coefficient, in: parent,
                    maximumDepth: maximumValueDepth, usage: &usage))
            }
            let polynomial = try OriginalSingularFieldPolynomial(context: parent, coefficients: coefficients,
                maximumDepth: maximumValueDepth, usage: &usage)
            let selected = OriginalSingularFieldRoot(polynomial: polynomial,
                isolation: .init(lower: root.isolation.lower, upper: root.isolation.upper,
                    excludesLower: root.isolation.excludesLowerEndpoint,
                    excludesUpper: root.isolation.excludesUpperEndpoint, depth: root.isolation.isolationDepth),
                admissionDomain: axis == .value ? .parameter : .coefficient(maximumDepth: maximumCoefficientDepth))
            return try OriginalSingularFieldContext(root: selected, usage: &usage)
        }
        context = result.value; self.maximumValueDepth = maximumValueDepth
        self.maximumCoefficientDepth = maximumCoefficientDepth
    }

    /// Retains the same domain after the creating operation owner leaves scope.
    public init<A: ExactScalarAdmission & ~Copyable>(retaining value: borrowing Value,
        maximumValueDepth: Int, maximumCoefficientDepth: Int,
        using admission: inout A) throws(ExactScalarFailure) {
        try admission.checkpoint()
        try Self.validateLimits(maximumValueDepth, maximumCoefficientDepth)
        try Self.validateDepth(value.depth, valueLimit: maximumValueDepth, coefficientLimit: maximumCoefficientDepth)
        context = try ExactScalarNumericAccess.withAdmission(&admission, inherited: value.depth) { _ in value.original.context }.value
        self.maximumValueDepth = maximumValueDepth; self.maximumCoefficientDepth = maximumCoefficientDepth
    }

    public func integer<I: BinaryInteger, A: ExactScalarAdmission & ~Copyable>(_ source: I, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try operation(using: &admission) { usage in
            try .constant(.originalInteger(source, usage: &usage), in: context,
                maximumDepth: maximumValueDepth, usage: &usage)
        }
    }
    public func binary64<A: ExactScalarAdmission & ~Copyable>(exactly source: Double, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try operation(using: &admission) { usage in
            guard source.isFinite else { throw ExactScalarFailure.invalidSource }
            return try .constant(.originalDouble(source, usage: &usage), in: context,
                maximumDepth: maximumValueDepth, usage: &usage)
        }
    }
    /// Imports an already exact rational coefficient without a floating conversion.
    public func rational<A: ExactScalarAdmission & ~Copyable>(exactly source: ExactRationalCoefficient,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        try operation(using: &admission) { usage in
            try .constant(source, in: context, maximumDepth: maximumValueDepth, usage: &usage)
        }
    }
    /// Returns only an exact rational square root in this original scalar domain.
    package func exactRationalSquareRoot<A: ExactScalarAdmission & ~Copyable>(
        of value: borrowing Value, using admission: inout A
    ) throws(ExactScalarFailure) -> Value? {
        let root = try decision(depth: mergedDepth(value.depth), using: &admission) { usage in
            try requireDomain(value)
            guard let rational = try value.original.rationalValue(usage: &usage) else {
                return nil as ExactRationalCoefficient?
            }
            return try rational.exactSquareRoot(usage: &usage)
        }
        guard let root else { return nil }
        return try rational(exactly: root, using: &admission)
    }
    public func generator<A: ExactScalarAdmission & ~Copyable>(using admission: inout A) throws(ExactScalarFailure) -> Value {
        try operation(using: &admission) { usage in
            guard case .extended(let root) = context.source else { throw ExactScalarFailure.unsupportedRepresentation }
            let zero = try OriginalSingularFieldElement.constant(.zero, in: root.polynomial.context, maximumDepth: maximumValueDepth, usage: &usage)
            let one = try OriginalSingularFieldElement.constant(.one, in: root.polynomial.context, maximumDepth: maximumValueDepth, usage: &usage)
            try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldElement.self, usage: &usage)
            let numerator = try OriginalSingularFieldPolynomial(context: root.polynomial.context,
                coefficients: [zero, one], maximumDepth: maximumValueDepth, usage: &usage)
            guard case .extended(_, let unit) = context.constantAuthority else { throw ExactScalarFailure.invalidEvidence }
            return OriginalSingularFieldElement(context: context, storage: .extended(numerator, unit))
        }
    }
    public func importing<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing Source, using admission: inout A) throws(ExactScalarFailure) -> Value {
        let depth = mergedDepth(source.depth)
        return try operation(depth: depth, using: &admission) { usage in
            if source.original.context === context { return source.original }
            if let constant = try source.original.rationalValue(usage: &usage) {
                return try .constant(constant, in: context, maximumDepth: maximumValueDepth, usage: &usage)
            }
            var candidate: OriginalSingularFieldContext? = context
            while let owner = candidate {
                try usage.consumeExactWork(1)
                if owner === source.original.context {
                    return try source.original.embedded(in: context, maximumDepth: maximumValueDepth, usage: &usage)
                }
                candidate = owner.parent
            }
            throw ExactScalarFailure.incompatibleDomain
        }
    }
    public func negated<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try operation(depth: mergedDepth(value.depth), using: &admission) { usage in
            try requireDomain(value)
            return try value.original.negated(maximumDepth: maximumValueDepth, usage: &usage)
        }
    }
    public func adding<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try operation(depth: mergedDepth(lhs.depth, rhs.depth), using: &admission) { usage in
            try requireDomain(lhs); try requireDomain(rhs)
            return try lhs.original.adding(rhs.original, maximumDepth: maximumValueDepth, usage: &usage)
        }
    }
    public func subtracting<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try operation(depth: mergedDepth(lhs.depth, rhs.depth), using: &admission) { usage in
            try requireDomain(lhs); try requireDomain(rhs)
            return try lhs.original.subtracting(rhs.original, maximumDepth: maximumValueDepth, usage: &usage)
        }
    }
    public func multiplying<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try operation(depth: mergedDepth(lhs.depth, rhs.depth), using: &admission) { usage in
            try requireDomain(lhs); try requireDomain(rhs)
            return try lhs.original.multiplied(by: rhs.original, maximumDepth: maximumValueDepth, usage: &usage)
        }
    }
    public func dividing<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try operation(depth: mergedDepth(lhs.depth, rhs.depth), using: &admission) { usage in
            try requireDomain(lhs); try requireDomain(rhs)
            guard try rhs.original.sign(maximumDepth: maximumValueDepth, usage: &usage) != .zero else { throw ExactScalarFailure.divisionByZero }
            return try lhs.original.divided(by: rhs.original, maximumDepth: maximumValueDepth, usage: &usage)
        }
    }
    public func sign<A: ExactScalarAdmission & ~Copyable>(of value: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> ExactSign {
        try decision(depth: mergedDepth(value.depth), using: &admission) { usage in
            try requireDomain(value)
            return Self.sign(try value.original.sign(maximumDepth: maximumValueDepth, usage: &usage))
        }
    }
    public func compare<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> ExactOrder {
        try decision(depth: mergedDepth(lhs.depth, rhs.depth), using: &admission) { usage in
            try requireDomain(lhs); try requireDomain(rhs)
            let difference = try lhs.original.subtracting(rhs.original, maximumDepth: maximumValueDepth, usage: &usage)
            switch try difference.sign(maximumDepth: maximumValueDepth, usage: &usage) {
            case .negative: return .less
            case .zero: return .equal
            case .positive: return .greater
            }
        }
    }

    private func operation<A: ExactScalarAdmission & ~Copyable>(depth: ExactScalarDepth? = nil, using admission: inout A,
        _ body: (inout ExactScalarRationalAdmission<A>) throws -> OriginalSingularFieldElement) throws(ExactScalarFailure) -> Value {
        let inherited = depth ?? originalDepth
        let result = try decisionResult(depth: inherited, using: &admission, body)
        return Value(original: result.value, depth: result.depth)
    }
    private func decision<A: ExactScalarAdmission & ~Copyable, R>(depth: ExactScalarDepth, using admission: inout A,
        _ body: (inout ExactScalarRationalAdmission<A>) throws -> R) throws(ExactScalarFailure) -> R {
        try decisionResult(depth: depth, using: &admission, body).value
    }
    private func decisionResult<A: ExactScalarAdmission & ~Copyable, R>(depth: ExactScalarDepth, using admission: inout A,
        _ body: (inout ExactScalarRationalAdmission<A>) throws -> R) throws(ExactScalarFailure) -> (value: R, depth: ExactScalarDepth) {
        try admission.checkpoint()
        try Self.validateDepth(depth, valueLimit: maximumValueDepth, coefficientLimit: maximumCoefficientDepth)
        return try ExactScalarNumericAccess.withAdmission(&admission, original: originalDepth, inherited: depth,
            maximum: .init(uncheckedValue: maximumValueDepth, coefficient: maximumCoefficientDepth), body)
    }
    private func requireDomain(_ value: borrowing Value) throws(ExactScalarFailure) {
        guard value.original.context === context else { throw .incompatibleDomain }
    }
    private func mergedDepth(_ a: ExactScalarDepth, _ b: ExactScalarDepth = .zero) -> ExactScalarDepth {
        .init(uncheckedValue: max(originalDepth.value, max(a.value, b.value)),
            coefficient: max(originalDepth.coefficient, max(a.coefficient, b.coefficient)))
    }
    private static func sign(_ sign: ExactAlgebraicRealRoot.Sign) -> ExactSign {
        switch sign { case .negative: .negative; case .zero: .zero; case .positive: .positive }
    }
    private static func validateLimits(_ value: Int, _ coefficient: Int) throws(ExactScalarFailure) {
        guard value >= 0, coefficient >= 0 else { throw .invalidSource }
    }
    private static func validateDepth(_ depth: ExactScalarDepth, valueLimit: Int, coefficientLimit: Int) throws(ExactScalarFailure) {
        guard depth.value <= valueLimit else { throw .resourceLimit(.valueDepth) }
        guard depth.coefficient <= coefficientLimit else { throw .resourceLimit(.coefficientDepth) }
    }
}
