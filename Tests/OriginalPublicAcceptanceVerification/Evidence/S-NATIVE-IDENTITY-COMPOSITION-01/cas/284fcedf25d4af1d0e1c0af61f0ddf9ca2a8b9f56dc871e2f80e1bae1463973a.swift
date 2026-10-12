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
                return try fraction(root.source.context.univariate.negated(n, using: &a), d, calculation: v.calculation, &a)
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
        case (.fraction(let ln, let ld), .fraction(let rn, _)):
            guard let root = context.root else { throw ExactScalarFailure.invalidEvidence }
            let p = root.source.context.univariate
            let common = try commonCalculation(l, r, &a)
            if kind == 3 {
                guard try polynomialSign(rn, at: r.calculation?.selectedRoot, &a) != .zero else { throw ExactScalarFailure.divisionByZero }
                return try fraction(ln, rn, calculation: common, &a)
            }
            let n: ExactPolynomial<Self>
            if kind == 2 { n = try p.multiplying(ln, rn, using: &a) }
            else {
                n = try kind == 0 ? p.adding(ln, rn, using: &a) : p.subtracting(ln, rn, using: &a)
            }
            return try fraction(n, ld, calculation: common, &a)
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
    public func dividing<A: ExactScalarAdmission & ~Copyable>(_ numerators: borrowing [Value], by divisor: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> [Value] {
        if numerators.isEmpty {
            try admission.checkpoint(); try admission.checkpoint()
            return []
        }
        let numerators = copy numerators, divisor = copy divisor
        return try scalarQuery(&admission) { a in
            let denominator = try admitted(divisor, &a)
            try ExactRootAccess.storage(numerators.count, Value.self, &a)
            var result: [Value] = []
            result.reserveCapacity(numerators.count)
            var inverse: Value?
            // Constant divisors retain the cheaper direct path; only algebraic inverses are shared.
            if numerators.count >= 3, case .fraction(let n, _) = denominator.storage {
                guard let root = context.root else { throw ExactScalarFailure.invalidEvidence }
                if try (root.source.context.univariate.degree(of: n, in: 0, using: &a) ?? 0) > 0 {
                    inverse = try operation(integer(1, using: &a), denominator, 3, &a)
                }
            }
            for numerator in numerators {
                try a.consumeWork(1)
                if let inverse { result.append(try operation(numerator, inverse, 2, &a)) }
                else { result.append(try operation(numerator, denominator, 3, &a)) }
            }
            return result
        }
    }
    public func sign<A: ExactScalarAdmission & ~Copyable>(of value: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> ExactSign {
        let value = copy value
        return try scalarQuery(&admission) { a in
            let v = try admitted(value, &a)
            switch v.storage {
            case .base(let b): return try context.base.sign(of: b, using: &a)
            case .fraction(let n, let d):
                // The only storage issuer already proves d == 1, including local inverses.
                try ExactRootAccess.admit(d.depth, &a)
                return try polynomialSign(n, at: v.calculation?.selectedRoot, &a)
            }
        }
    }
    public func compare<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> ExactOrder {
        let lhs = copy lhs, rhs = copy rhs
        return try scalarQuery(&admission) { a in
            let l = try admitted(lhs, &a), r = try admitted(rhs, &a)
            if case .base(let x) = l.storage, case .base(let y) = r.storage {
                return try context.base.compare(x, y, using: &a)
            }
            let difference = try operation(l, r, 1, &a)
            let sign = try self.sign(of: difference, using: &a)
            return sign == .zero ? .equal : sign == .negative ? .less : .greater
        }
    }
}
