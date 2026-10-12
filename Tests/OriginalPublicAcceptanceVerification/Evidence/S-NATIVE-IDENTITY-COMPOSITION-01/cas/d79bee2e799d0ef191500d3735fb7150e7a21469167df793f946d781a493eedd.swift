#if EXACT_DOMAIN_ISOLATED_VERIFICATION
import L0
#endif

extension ExactParameterDomain {
    public func union<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing ExactParameterSet<F>,
        _ rhs: borrowing ExactParameterSet<F>, using admission: inout A)
        throws(ExactParameterDomainFailure) -> ExactParameterSet<F> {
        let l = copy lhs; let r = copy rhs
        return try ExactParameterDomainAccess.run(&admission, depth: context.depth) { a in
            try require(l, &a); try require(r, &a)
            let capacity = try ExactParameterDomainAccess.add(l.intervalCount, r.intervalCount)
            try ExactParameterDomainAccess.storage(capacity, ExactParameterInterval<F.Value>.self, &a)
            var output: [ExactParameterInterval<F.Value>] = []; output.reserveCapacity(capacity)
            var i = 0; var j = 0
            while i < l.intervalCount || j < r.intervalCount {
                try a.consumeWork(1)
                if j == r.intervalCount { try append(l.storage[i], to: &output, &a); i += 1 }
                else if i == l.intervalCount { try append(r.storage[j], to: &output, &a); j += 1 }
                else {
                    let order = try ExactParameterDomainAccess.compare(l.storage[i].lower, r.storage[j].lower,
                        field: context.field, using: &a)
                    if order != .greater { try append(l.storage[i], to: &output, &a); i += 1 }
                    else { try append(r.storage[j], to: &output, &a); j += 1 }
                }
            }
            return ExactParameterSet(context: context, storage: output,
                depth: try ExactParameterDomainAccess.joined(l.depth, r.depth))
        }
    }
    func overlap<A: ExactScalarAdmission & ~Copyable>(_ l: ExactParameterInterval<F.Value>,
        _ r: ExactParameterInterval<F.Value>, _ a: inout A) throws -> ExactParameterInterval<F.Value>? {
        let low = try ExactParameterDomainAccess.compare(l.lower, r.lower, field: context.field, using: &a)
        let high = try ExactParameterDomainAccess.compare(l.upper, r.upper, field: context.field, using: &a)
        let lo = low == .less ? r.lower : l.lower
        let hi = high == .greater ? r.upper : l.upper
        let il = low == .equal ? l.includesLower && r.includesLower : (low == .less ? r.includesLower : l.includesLower)
        let iu = high == .equal ? l.includesUpper && r.includesUpper : (high == .greater ? r.includesUpper : l.includesUpper)
        let order = try ExactParameterDomainAccess.compare(lo, hi, field: context.field, using: &a)
        guard order != .greater, order != .equal || (il && iu) else { return nil }
        return .init(lower: lo, upper: hi, includesLower: il, includesUpper: iu,
            isEmpty: false, depth: try ExactParameterDomainAccess.joined(l.depth, r.depth))
    }
    public func intersection<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing ExactParameterSet<F>,
        _ rhs: borrowing ExactParameterSet<F>, using admission: inout A)
        throws(ExactParameterDomainFailure) -> ExactParameterSet<F> {
        let l = copy lhs; let r = copy rhs
        return try ExactParameterDomainAccess.run(&admission, depth: context.depth) { a in
            try require(l, &a); try require(r, &a)
            let capacity = try ExactParameterDomainAccess.add(l.intervalCount, r.intervalCount)
            try ExactParameterDomainAccess.storage(capacity, ExactParameterInterval<F.Value>.self, &a)
            var output: [ExactParameterInterval<F.Value>] = []; output.reserveCapacity(capacity)
            var i = 0; var j = 0
            while i < l.intervalCount && j < r.intervalCount {
                try a.consumeWork(1)
                if let item = try overlap(l.storage[i], r.storage[j], &a) { try append(item, to: &output, &a) }
                let order = try ExactParameterDomainAccess.compare(l.storage[i].upper, r.storage[j].upper,
                    field: context.field, using: &a)
                if order != .greater { i += 1 }; if order != .less { j += 1 }
            }
            return ExactParameterSet(context: context, storage: output,
                depth: try ExactParameterDomainAccess.joined(l.depth, r.depth))
        }
    }
    public func difference<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing ExactParameterSet<F>,
        _ rhs: borrowing ExactParameterSet<F>, using admission: inout A)
        throws(ExactParameterDomainFailure) -> ExactParameterSet<F> {
        let l = copy lhs; let r = copy rhs
        return try ExactParameterDomainAccess.run(&admission, depth: context.depth) { a in
            try require(l, &a); try require(r, &a)
            // Each disjoint cut can add at most one component across the entire left union.
            let capacity = try ExactParameterDomainAccess.add(l.intervalCount, r.intervalCount)
            try ExactParameterDomainAccess.storage(capacity, ExactParameterInterval<F.Value>.self, &a)
            var output: [ExactParameterInterval<F.Value>] = []; output.reserveCapacity(capacity)
            var j = 0
            for source in l.storage {
                try a.consumeWork(1)
                var remaining: ExactParameterInterval<F.Value>? = source
                while j < r.intervalCount, let tail = remaining {
                    try a.consumeWork(1)
                    let cut = r.storage[j]
                    let before = try ExactParameterDomainAccess.compare(cut.upper, tail.lower, field: context.field, using: &a)
                    if before == .less || (before == .equal && !(cut.includesUpper && tail.includesLower)) {
                        j += 1; continue
                    }
                    let after = try ExactParameterDomainAccess.compare(cut.lower, tail.upper, field: context.field, using: &a)
                    if after == .greater || (after == .equal && !(cut.includesLower && tail.includesUpper)) { break }
                    guard let shared = try overlap(tail, cut, &a) else { j += 1; continue }
                    let leftOrder = try ExactParameterDomainAccess.compare(tail.lower, shared.lower, field: context.field, using: &a)
                    if leftOrder == .less || (leftOrder == .equal && tail.includesLower && !shared.includesLower) {
                        try append(.init(lower: tail.lower, upper: shared.lower, includesLower: tail.includesLower,
                            includesUpper: !shared.includesLower, isEmpty: false, depth: shared.depth), to: &output, &a)
                    }
                    let rightOrder = try ExactParameterDomainAccess.compare(shared.upper, tail.upper, field: context.field, using: &a)
                    if rightOrder == .less || (rightOrder == .equal && tail.includesUpper && !shared.includesUpper) {
                        remaining = .init(lower: shared.upper, upper: tail.upper, includesLower: !shared.includesUpper,
                            includesUpper: tail.includesUpper, isEmpty: false, depth: shared.depth)
                        j += 1
                    } else { remaining = nil }
                }
                if let remaining { try append(remaining, to: &output, &a) }
            }
            return ExactParameterSet(context: context, storage: output,
                depth: try ExactParameterDomainAccess.joined(l.depth, r.depth))
        }
    }
}
