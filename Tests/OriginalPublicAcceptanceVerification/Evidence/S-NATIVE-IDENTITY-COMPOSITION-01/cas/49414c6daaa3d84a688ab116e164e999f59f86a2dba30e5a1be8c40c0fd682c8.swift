#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Retains complete descendant evidence and all original-coordinate chart lifts.
public struct OriginalAffineChildDomainCover<S: Sendable, C: OriginalChartFamilyQuerying>: OriginalChartFamilyQuerying {
    public typealias Source = S
    public typealias Field = C.Field
    public typealias Occurrence = OriginalAffineChildDomainOccurrence<S, C.Occurrence, Field>
    public let childFamily: C
    public let support: OriginalParameterSelection<S, Field>
    public let request: OriginalParameterSelection<S, Field>
    public let effective: OriginalParameterSelection<S, Field>
    public let correspondence: OriginalParameterTransport<S, Field>
    let reverse: OriginalParameterTransport<S, Field>
    public var source: OriginalSourceBinding<S> { support.frame.source }
    public var templateCount: Int { childFamily.templateCount }
    public var integerFamilyRank: Int { childFamily.integerFamilyRank }

    public func member<A: ExactScalarAdmission & ~Copyable>(template: Int,
        cycles: borrowing [OriginalParameterCycle], limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> Occurrence {
        let cycles = copy cycles
        return try OriginalDomainAccess.run(&admission) { a in
            try DefaultOriginalParameterTransporter<S, Field>().admitted(correspondence, limits: limits, using: &a)
            guard cycles.count == support.arity else { throw OriginalDomainIdentityFailure.invalidDomain }
            try OriginalDomainAccess.storage(cycles.count, OriginalParameterCycle.self, &a)
            var childCycles = cycles
            let q = ExactRationalScalarDomain(), f = support.frame.scalarField
            for axis in cycles.indices {
                try a.consumeWork(1)
                let value = try f.sign(of: correspondence.gains[axis], using: &a) == .positive
                    ? cycles[axis].original : q.negated(cycles[axis].original, using: &a)
                childCycles[correspondence.permutation[axis]] = try .init(exact: value, using: &a)
            }
            let occurrence = try childFamily.member(template: template, cycles: childCycles, limits: limits, using: &a)
            try OriginalDomainAccess.storage(1, Occurrence.self, &a)
            return .init(child: occurrence, correspondence: correspondence)
        }
    }
    public func incident<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [Field.Value],
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> [Occurrence] {
        let tuple = copy tuple
        return try OriginalDomainAccess.run(&admission) { a in
            let t = DefaultOriginalParameterTransporter<S, Field>()
            try t.admitted(correspondence, limits: limits, using: &a)
            guard try effective.contains(tuple, limits: limits, using: &a) else { return [] }
            let childTuple = try t.forward(tuple, through: reverse, limits: limits, using: &a)
            let children = try childFamily.incident(at: childTuple, limits: limits, using: &a)
            guard !children.isEmpty else { throw OriginalDomainIdentityFailure.incompleteCoverage }
            guard children.count <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            try OriginalDomainAccess.storage(children.count, Occurrence.self, &a)
            var result: [Occurrence] = []; result.reserveCapacity(children.count)
            for occurrence in children {
                try a.consumeWork(1); result.append(.init(child: occurrence, correspondence: correspondence))
            }
            return result
        }
    }

    // Only source-specific issuers may supply a checked affine source command.
    static func prepared<A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<S>, child: C,
        childSupport: OriginalParameterSelection<C.Source, Field>, permutation: [Int],
        gains: [Field.Value], offsets: [Field.Value],
        requested: [[ExactParameterInterval<Field.Value>]]?, limits: OriginalDomainIdentityLimits,
        using a: inout A) throws -> Self {
        let n = childSupport.arity, f = childSupport.frame.scalarField
        guard n > 0, permutation.count == n, gains.count == n, offsets.count == n else {
            throw OriginalDomainIdentityFailure.invalidDomain
        }
        guard child.support.sharesFrame(with: childSupport), child.support.sharesFrame(with: child.effective) else {
            throw OriginalDomainIdentityFailure.foreignOwner
        }
        guard child.templateCount <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
        guard child.integerFamilyRank <= limits.maximumFamilies else { throw OriginalDomainIdentityFailure.familyLimit }
        let t = DefaultOriginalParameterTransporter<S, Field>()
        try OriginalDomainAccess.storage(n, [ExactParameterInterval<Field.Value>].self, &a)
        try OriginalDomainAccess.storage(n, [ExactParameterInterval<Field.Value>].self, &a)
        try OriginalDomainAccess.storage(n, OriginalCoordinateSemantics.self, &a)
        var localIntervals: [[ExactParameterInterval<Field.Value>]] = []
        var parentIntervals: [[ExactParameterInterval<Field.Value>]] = []
        var semantics: [OriginalCoordinateSemantics] = []
        localIntervals.reserveCapacity(n); parentIntervals.reserveCapacity(n); semantics.reserveCapacity(n)
        for i in 0..<n {
            try a.consumeWork(1)
            let j = permutation[i]
            guard j >= 0, j < n else { throw OriginalDomainIdentityFailure.invalidDomain }
            for previous in 0..<i {
                try a.consumeWork(1)
                guard permutation[previous] != j else { throw OriginalDomainIdentityFailure.singularTransport }
            }
            try OriginalDomainAccess.storage(childSupport.axes[i].intervalCount, ExactParameterInterval<Field.Value>.self, &a)
            localIntervals.append(Array(childSupport.axes[i].intervals))
            let domain = try ExactParameterDomain(field: f, depth: childSupport.axes[j].depth, using: &a)
            let mapped = try t.image(childSupport.axes[j], gain: gains[i], offset: offsets[i], domain: domain, field: f, &a)
            try OriginalDomainAccess.storage(mapped.intervalCount, ExactParameterInterval<Field.Value>.self, &a)
            parentIntervals.append(Array(mapped.intervals))
            semantics.append(childSupport.frame.coordinateSemantics[j])
        }
        try OriginalDomainAccess.storage(n, OriginalCoordinateSemantics.self, &a)
        let localFrame = try t.frame(source: source, field: f, support: localIntervals,
            semantics: Array(childSupport.frame.coordinateSemantics), limits: limits, using: &a)
        let parentFrame = try t.frame(source: source, field: f, support: parentIntervals,
            semantics: semantics, limits: limits, using: &a)
        let support = try parentFrame.fullSelection(limits: limits, using: &a)
        let request = try requested.map { try parentFrame.selection(intervals: $0, limits: limits, using: &a) } ?? support
        let effective = try request.intersection(support, limits: limits, using: &a)
        let full = try t.affine(from: localFrame.fullSelection(limits: limits, using: &a),
            to: parentFrame, permutation: permutation, gains: gains, offsets: offsets, limits: limits, using: &a)
        let inverse = try t.inverse(full, limits: limits, using: &a)
        let reverse = try t.restrict(inverse, to: effective, limits: limits, using: &a)
        try OriginalDomainAccess.storage(n, [ExactParameterInterval<Field.Value>].self, &a)
        var pulledIntervals: [[ExactParameterInterval<Field.Value>]] = []
        pulledIntervals.reserveCapacity(n)
        for axis in reverse.image.axes {
            try a.consumeWork(1)
            try OriginalDomainAccess.storage(axis.intervalCount, ExactParameterInterval<Field.Value>.self, &a)
            pulledIntervals.append(Array(axis.intervals))
        }
        let pulled = try childSupport.frame.selection(intervals: pulledIntervals, limits: limits, using: &a)
        guard try pulled.difference(child.effective, limits: limits, using: &a).isEmpty else {
            throw OriginalDomainIdentityFailure.incompleteCoverage
        }
        let correspondence = try t.inverse(reverse, limits: limits, using: &a)
        try OriginalDomainAccess.storage(1, Self.self, &a)
        return .init(childFamily: child, support: support, request: request, effective: effective,
            correspondence: correspondence, reverse: reverse)
    }
}
