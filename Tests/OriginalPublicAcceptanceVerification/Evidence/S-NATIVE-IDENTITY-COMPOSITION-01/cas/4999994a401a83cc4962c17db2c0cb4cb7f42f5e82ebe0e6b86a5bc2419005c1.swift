public protocol ExactScalarOrdering: Sendable {
    associatedtype Value: Sendable
    func sign<A: ExactScalarAdmission & ~Copyable>(of value: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> ExactSign
    func compare<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> ExactOrder
}

public func exactEquality<F: ExactScalarOrdering, A: ExactScalarAdmission & ~Copyable>(_ field: F, _ lhs: borrowing F.Value, _ rhs: borrowing F.Value, using admission: inout A) throws(ExactScalarFailure) -> Bool {
    try field.compare(lhs, rhs, using: &admission) == .equal
}

public func exactZero<F: ExactScalarOrdering, A: ExactScalarAdmission & ~Copyable>(_ field: F, _ value: borrowing F.Value, using admission: inout A) throws(ExactScalarFailure) -> Bool {
    try field.sign(of: value, using: &admission) == .zero
}
