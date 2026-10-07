public protocol ExactScalarArithmetic: Sendable {
    associatedtype Value: Sendable
    func integer<I: BinaryInteger, A: ExactScalarAdmission & ~Copyable>(_ source: I, using admission: inout A) throws(ExactScalarFailure) -> Value
    func binary64<A: ExactScalarAdmission & ~Copyable>(exactly source: Double, using admission: inout A) throws(ExactScalarFailure) -> Value
    func negated<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value
    func adding<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value
    func subtracting<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value
    func multiplying<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value
    func dividing<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value
}
