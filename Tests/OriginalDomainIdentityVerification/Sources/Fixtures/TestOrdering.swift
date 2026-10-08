import L0

/// Independent integer oracle also exercises incompatible and indeterminate comparisons.
struct TestOrdering: ExactScalarOrdering {
    typealias Value = TestOrderedValue
    let field: Int
    let unresolved: Bool
    init(field: Int = 0, unresolved: Bool = false) { self.field = field; self.unresolved = unresolved }
    func sign<A: ExactScalarAdmission & ~Copyable>(of value: borrowing Value, using a: inout A)
        throws(ExactScalarFailure) -> ExactSign {
        try a.consumeWork(1)
        guard value.field == field else { throw .incompatibleDomain }
        return value.number == 0 ? .zero : (value.number < 0 ? .negative : .positive)
    }
    func compare<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value,
        using a: inout A) throws(ExactScalarFailure) -> ExactOrder {
        _ = try sign(of: lhs, using: &a); _ = try sign(of: rhs, using: &a)
        if unresolved { throw .unresolved }
        return lhs.number == rhs.number ? .equal : (lhs.number < rhs.number ? .less : .greater)
    }
}
