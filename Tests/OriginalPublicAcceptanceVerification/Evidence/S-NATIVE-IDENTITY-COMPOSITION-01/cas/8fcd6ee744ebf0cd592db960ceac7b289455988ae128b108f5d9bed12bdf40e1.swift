#if EXACT_DOMAIN_ISOLATED_VERIFICATION
import L0
#endif

extension ExactParameterDomain {
    func membership<A: ExactScalarAdmission & ~Copyable>(_ value: F.Value,
        _ set: ExactParameterSet<F>, queryField: F? = nil, _ a: inout A) throws -> Bool {
        let field = queryField ?? set.context.field
        for item in set.storage {
            try a.consumeWork(1)
            let lo = try ExactParameterDomainAccess.compare(.finite(value), item.lower, field: field, using: &a)
            if lo == .less || (lo == .equal && !item.includesLower) { return false }
            let hi = try ExactParameterDomainAccess.compare(.finite(value), item.upper, field: field, using: &a)
            if hi == .less || (hi == .equal && item.includesUpper) { return true }
        }
        return false
    }
    public func contains<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing F.Value,
        in selection: borrowing ExactParameterSet<F>, using admission: inout A)
        throws(ExactParameterDomainFailure) -> Bool {
        let v = copy value; let s = copy selection
        return try ExactParameterDomainAccess.run(&admission, depth: context.depth) { a in
            try require(s, &a)
            _ = try context.field.sign(of: v, using: &a)
            return try membership(v, s, &a)
        }
    }
    public func setEqual<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing ExactParameterSet<F>,
        _ rhs: borrowing ExactParameterSet<F>, using admission: inout A)
        throws(ExactParameterDomainFailure) -> Bool {
        let l = copy lhs; let r = copy rhs
        return try ExactParameterDomainAccess.run(&admission, depth: context.depth) { a in
            try require(l, &a); try require(r, &a)
            guard l.intervalCount == r.intervalCount else { return false }
            for i in l.storage.indices {
                try a.consumeWork(1)
                let x = l.storage[i]; let y = r.storage[i]
                guard x.includesLower == y.includesLower, x.includesUpper == y.includesUpper else { return false }
                guard try ExactParameterDomainAccess.compare(x.lower, y.lower, field: context.field, using: &a) == .equal,
                    try ExactParameterDomainAccess.compare(x.upper, y.upper, field: context.field, using: &a) == .equal else { return false }
            }
            return true
        }
    }
    public func product<A: ExactScalarAdmission & ~Copyable>(axes: borrowing [ExactParameterSet<F>],
        using admission: inout A) throws(ExactParameterDomainFailure) -> ExactParameterProduct<F> {
        let input = copy axes
        return try ExactParameterDomainAccess.run(&admission, depth: context.depth) { a in
            var depth = context.depth
            var empty = false
            for axis in input {
                try a.consumeWork(1)
                empty = empty || axis.isEmpty
                depth = try ExactParameterDomainAccess.joined(depth, axis.depth)
                try a.admitDepth(value: depth.value, coefficient: depth.coefficient)
            }
            // Sharing the immutable input array retains each distinct axis owner without copying its intervals.
            return ExactParameterProduct(context: context, storage: input, depth: depth, isEmpty: empty)
        }
    }
    public func contains<A: ExactScalarAdmission & ~Copyable>(tuple: borrowing [F.Value],
        in selection: borrowing ExactParameterProduct<F>, using admission: inout A)
        throws(ExactParameterDomainFailure) -> Bool {
        let values = copy tuple; let s = copy selection
        return try ExactParameterDomainAccess.run(&admission, depth: context.depth) { a in
            guard s.context === context else { throw ExactParameterDomainFailure.foreignOwner }
            guard values.count == s.arity else { throw ExactParameterDomainFailure.invalidArity }
            try a.admitDepth(value: s.depth.value, coefficient: s.depth.coefficient)
            // Validate every axis even when another one is empty or excludes the tuple.
            var accepted = true
            for i in values.indices {
                try a.consumeWork(1)
                _ = try s.storage[i].context.field.sign(of: values[i], using: &a)
                if try !membership(values[i], s.storage[i], &a) { accepted = false }
            }
            return accepted
        }
    }
}
