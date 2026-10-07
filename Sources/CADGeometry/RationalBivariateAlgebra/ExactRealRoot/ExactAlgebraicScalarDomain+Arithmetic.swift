#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension ExactAlgebraicScalarDomain {
    func admitted(_ source: Value, _ a: inout ExactRootBorrowedAdmission) throws -> Value {
        try embedded(source, &a)
    }
    public func negated<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        let value = copy value
        return try scalarQuery(&admission) { a in
            let v = try admitted(value, &a)
            switch v.storage {
            case .base(let b): return Value(context: context, storage: .base(try context.base.negated(b, using: &a)), depth: a.depth)
            case .fraction(let n, let d):
                guard let root = context.root else { throw ExactScalarFailure.invalidEvidence }
                return try fraction(root.source.context.univariate.negated(n, using: &a), d, &a)
            }
        }
    }
    func operation(_ lhs: Value, _ rhs: Value, _ kind: Int, _ a: inout ExactRootBorrowedAdmission) throws -> Value {
        let l = try admitted(lhs, &a), r = try admitted(rhs, &a)
        switch (l.storage, r.storage) {
        case (.base(let x), .base(let y)):
            let value: Base.Value
            switch kind {
            case 0: value = try context.base.adding(x, y, using: &a)
            case 1: value = try context.base.subtracting(x, y, using: &a)
            case 2: value = try context.base.multiplying(x, y, using: &a)
            default: value = try context.base.dividing(x, y, using: &a)
            }
            return Value(context: context, storage: .base(value), depth: a.depth)
        case (.fraction(let ln, let ld), .fraction(let rn, let rd)):
            guard let root = context.root else { throw ExactScalarFailure.invalidEvidence }
            let p = root.source.context.univariate
            if kind == 3 {
                guard try polynomialSign(rn, &a) != .zero else { throw ExactScalarFailure.divisionByZero }
                return try fraction(p.multiplying(ln, rd, using: &a), p.multiplying(ld, rn, using: &a), &a)
            }
            let n: ExactPolynomial<Self>
            if kind == 2 { n = try p.multiplying(ln, rn, using: &a) }
            else {
                let left = try p.multiplying(ln, rd, using: &a), right = try p.multiplying(rn, ld, using: &a)
                n = try kind == 0 ? p.adding(left, right, using: &a) : p.subtracting(left, right, using: &a)
            }
            return try fraction(n, p.multiplying(ld, rd, using: &a), &a)
        default: throw ExactScalarFailure.invalidEvidence
        }
    }
    public func adding<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        let lhs = copy lhs, rhs = copy rhs
        return try scalarQuery(&admission) { try operation(lhs, rhs, 0, &$0) }
    }
    public func subtracting<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        let lhs = copy lhs, rhs = copy rhs
        return try scalarQuery(&admission) { try operation(lhs, rhs, 1, &$0) }
    }
    public func multiplying<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        let lhs = copy lhs, rhs = copy rhs
        return try scalarQuery(&admission) { try operation(lhs, rhs, 2, &$0) }
    }
    public func dividing<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value {
        let lhs = copy lhs, rhs = copy rhs
        return try scalarQuery(&admission) { try operation(lhs, rhs, 3, &$0) }
    }
    public func sign<A: ExactScalarAdmission & ~Copyable>(of value: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> ExactSign {
        let value = copy value
        return try scalarQuery(&admission) { a in
            let v = try admitted(value, &a)
            switch v.storage {
            case .base(let b): return try context.base.sign(of: b, using: &a)
            case .fraction(let n, let d):
                let ds = try polynomialSign(d, &a)
                guard ds != .zero else { throw ExactScalarFailure.divisionByZero }
                let ns = try polynomialSign(n, &a)
                return ns == .zero ? .zero : ns == ds ? .positive : .negative
            }
        }
    }
    public func compare<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> ExactOrder {
        let lhs = copy lhs, rhs = copy rhs
        return try scalarQuery(&admission) { a in
            let difference = try operation(lhs, rhs, 1, &a)
            let sign = try self.sign(of: difference, using: &a)
            return sign == .zero ? .equal : sign == .negative ? .less : .greater
        }
    }
}
