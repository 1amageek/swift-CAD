#if EXACT_DOMAIN_ISOLATED_VERIFICATION
import L0
#endif

public struct ExactParameterDomain<F: ExactScalarOrdering>: ExactParameterDomainConstructing, ExactParameterDomainQuerying {
    public typealias Field = F
    let context: ExactParameterDomainContext<F>
    public init<A: ExactScalarAdmission & ~Copyable>(field: F, depth: ExactScalarDepth,
        using admission: inout A) throws(ExactParameterDomainFailure) {
        context = try ExactParameterDomainAccess.run(&admission, depth: depth) { a in
            let payload = try exactScalarPayloadBytes(count: 1, of: (F, ExactScalarDepth).self)
            let header = try exactScalarPayloadBytes(count: 2, of: UnsafeRawPointer.self)
            try a.retainStorage(bytes: ExactParameterDomainAccess.add(payload, header))
            return ExactParameterDomainContext(field: field, depth: depth)
        }
    }
    public init<A: ExactScalarAdmission & ~Copyable>(retaining selection: borrowing ExactParameterSet<F>,
        using admission: inout A) throws(ExactParameterDomainFailure) {
        let selected = copy selection
        context = try ExactParameterDomainAccess.run(&admission, depth: selected.depth) { _ in selected.context }
    }
    public func interval<A: ExactScalarAdmission & ~Copyable>(lower: ExactParameterBound<F.Value>,
        upper: ExactParameterBound<F.Value>, includesLower: Bool = true, includesUpper: Bool = true,
        using admission: inout A) throws(ExactParameterDomainFailure) -> ExactParameterInterval<F.Value> {
        try .checked(field: context.field, lower: lower, upper: upper,
            includesLower: includesLower, includesUpper: includesUpper, depth: context.depth, using: &admission)
    }
    func require<A: ExactScalarAdmission & ~Copyable>(_ set: ExactParameterSet<F>, _ a: inout A) throws {
        guard set.context === context else { throw ExactParameterDomainFailure.foreignOwner }
        try a.admitDepth(value: set.depth.value, coefficient: set.depth.coefficient)
    }
    public func empty<A: ExactScalarAdmission & ~Copyable>(using admission: inout A)
        throws(ExactParameterDomainFailure) -> ExactParameterSet<F> {
        try ExactParameterDomainAccess.run(&admission, depth: context.depth) { _ in
            ExactParameterSet(context: context, storage: [], depth: context.depth)
        }
    }
    public func set<A: ExactScalarAdmission & ~Copyable>(intervals: borrowing [ExactParameterInterval<F.Value>],
        using admission: inout A) throws(ExactParameterDomainFailure) -> ExactParameterSet<F> {
        let input = copy intervals
        return try ExactParameterDomainAccess.run(&admission, depth: context.depth) { a in
            // Raw scalar intervals are explicitly bound here; every finite endpoint is revalidated.
            try ExactParameterDomainAccess.storage(input.count, ExactParameterInterval<F.Value>.self, &a)
            var sorted: [ExactParameterInterval<F.Value>] = []; sorted.reserveCapacity(input.count)
            var depth = context.depth
            for item in input {
                try a.consumeWork(1)
                depth = try ExactParameterDomainAccess.joined(depth, item.depth)
                try a.admitDepth(value: depth.value, coefficient: depth.coefficient)
                let checked = try ExactParameterInterval.checked(field: context.field, lower: item.lower, upper: item.upper,
                    includesLower: item.includesLower, includesUpper: item.includesUpper, depth: depth, using: &a)
                if item.isEmpty { continue }
                var index = sorted.count
                while index > 0 {
                    try a.consumeWork(1)
                    let order = try ExactParameterDomainAccess.compare(checked.lower, sorted[index - 1].lower,
                        field: context.field, using: &a)
                    if order != .less { break }
                    index -= 1
                }
                // This admitted scratch buffer is unique. Insertion shifts, never duplicates owners.
                sorted.insert(checked, at: index)
            }
            try ExactParameterDomainAccess.storage(sorted.count, ExactParameterInterval<F.Value>.self, &a)
            var output: [ExactParameterInterval<F.Value>] = []; output.reserveCapacity(sorted.count)
            for item in sorted { try append(item, to: &output, &a) }
            return ExactParameterSet(context: context, storage: output, depth: depth)
        }
    }
    func append<A: ExactScalarAdmission & ~Copyable>(_ next: ExactParameterInterval<F.Value>,
        to output: inout [ExactParameterInterval<F.Value>], _ a: inout A) throws {
        try a.consumeWork(1)
        guard !next.isEmpty else { return }
        guard let last = output.last else { output.append(next); return }
        let gap = try ExactParameterDomainAccess.compare(last.upper, next.lower, field: context.field, using: &a)
        if gap == .less || (gap == .equal && !last.includesUpper && !next.includesLower) {
            output.append(next); return
        }
        let low = try ExactParameterDomainAccess.compare(last.lower, next.lower, field: context.field, using: &a)
        let high = try ExactParameterDomainAccess.compare(last.upper, next.upper, field: context.field, using: &a)
        output[output.count - 1] = .init(lower: last.lower,
            upper: high == .less ? next.upper : last.upper,
            includesLower: last.includesLower || (low == .equal && next.includesLower),
            includesUpper: high == .less ? next.includesUpper : (high == .equal ? last.includesUpper || next.includesUpper : last.includesUpper),
            isEmpty: false, depth: try ExactParameterDomainAccess.joined(last.depth, next.depth))
    }
}
