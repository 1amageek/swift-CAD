/// Exact Q arithmetic over canonical retained integer-ratio values.
public struct ExactRationalScalarDomain: ExactScalarArithmetic, ExactScalarOrdering, ExactScalarImporting {
    public typealias Value = ExactRationalCoefficient
    public typealias Source = ExactRationalCoefficient
    public init() {}

    public func integer<I: BinaryInteger, A: ExactScalarAdmission & ~Copyable>(_ source: I, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try ExactScalarNumericAccess.withAdmission(&admission) { usage in
            try Value.originalInteger(source, usage: &usage)
        }.value
    }
    public func binary64<A: ExactScalarAdmission & ~Copyable>(exactly source: Double, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try ExactScalarNumericAccess.withAdmission(&admission) { usage in
            guard source.isFinite else { throw ExactScalarFailure.invalidSource }
            return try Value.originalDouble(source, usage: &usage)
        }.value
    }
    public func canonical<A: ExactScalarAdmission & ~Copyable>(sign: Int, numerator: [UInt32], denominator: [UInt32], using admission: inout A) throws(ExactScalarFailure) -> Value {
        try ExactScalarNumericAccess.withAdmission(&admission) { usage in
            try Value(canonicalSign: sign, numeratorWords: numerator, denominatorWords: denominator, usage: &usage)
        }.value
    }
    public func importing<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing Source, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try ExactScalarNumericAccess.withAdmission(&admission) { usage in
            try usage.consumeExactWork(exactScalarCount(source.numerator.words.count, source.denominator.words.count))
            // Returning an owned value retains the existing immutable buffers; no payload copy is made.
            return copy source
        }.value
    }
    public func negated<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try ExactScalarNumericAccess.withAdmission(&admission) { _ in value.negated }.value
    }
    public func adding<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try ExactScalarNumericAccess.withAdmission(&admission) { usage in try lhs.adding(rhs, usage: &usage) }.value
    }
    public func subtracting<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try ExactScalarNumericAccess.withAdmission(&admission) { usage in try lhs.subtracting(rhs, usage: &usage) }.value
    }
    public func multiplying<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try ExactScalarNumericAccess.withAdmission(&admission) { usage in try lhs.multiplied(by: rhs, usage: &usage) }.value
    }
    public func dividing<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try ExactScalarNumericAccess.withAdmission(&admission) { usage in
            guard !rhs.isZero else { throw ExactScalarFailure.divisionByZero }
            return try lhs.divided(by: rhs, usage: &usage)
        }.value
    }
    public func sign<A: ExactScalarAdmission & ~Copyable>(of value: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> ExactSign {
        try ExactScalarNumericAccess.withAdmission(&admission) { _ in
            value.isPositive ? ExactSign.positive : value.isNegative ? ExactSign.negative : ExactSign.zero
        }.value
    }
    public func compare<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> ExactOrder {
        try ExactScalarNumericAccess.withAdmission(&admission) { usage in
            if lhs.sign != rhs.sign { return lhs.sign < rhs.sign ? ExactOrder.less : ExactOrder.greater }
            if lhs.sign == 0 { return ExactOrder.equal }
            if lhs.denominator.words.count == rhs.denominator.words.count {
                try usage.consumeExactWork(lhs.denominator.words.count)
                if lhs.denominator == rhs.denominator {
                    try usage.consumeExactWork(max(lhs.numerator.words.count, rhs.numerator.words.count))
                    let order = lhs.numerator.compared(to: rhs.numerator)
                    if order == 0 { return ExactOrder.equal }
                    return (order < 0) == (lhs.sign > 0) ? ExactOrder.less : ExactOrder.greater
                }
            }
            let difference = try lhs.subtracting(rhs, usage: &usage)
            return difference.isPositive ? ExactOrder.greater : difference.isNegative ? ExactOrder.less : ExactOrder.equal
        }.value
    }
}
