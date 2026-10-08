public protocol ExactScalarArithmetic: Sendable {
    associatedtype Value: Sendable
    func integer<I: BinaryInteger, A: ExactScalarAdmission & ~Copyable>(_ source: I, using admission: inout A) throws(ExactScalarFailure) -> Value
    func binary64<A: ExactScalarAdmission & ~Copyable>(exactly source: Double, using admission: inout A) throws(ExactScalarFailure) -> Value
    func negated<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value
    func adding<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value
    func subtracting<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value
    func multiplying<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value
    func dividing<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value
    /// Ordered quotients by one divisor; a failure never publishes a partial array.
    func dividing<A: ExactScalarAdmission & ~Copyable>(_ numerators: borrowing [Value], by divisor: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> [Value]
}

extension ExactScalarArithmetic {
    public func dividing<A: ExactScalarAdmission & ~Copyable>(_ numerators: borrowing [Value], by divisor: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> [Value] {
        try admission.checkpoint()
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: numerators.count, of: Value.self))
        var result: [Value] = []
        result.reserveCapacity(numerators.count)
        for i in numerators.indices {
            try admission.consumeWork(1)
            result.append(try dividing(numerators[i], divisor, using: &admission))
        }
        try admission.checkpoint()
        return result
    }
}
