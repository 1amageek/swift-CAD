#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

extension OriginalParameterSelection {
    /// Exact coordinate-set image across explicitly retained roles. This operation
    /// asserts no common authored coordinate, source-law equality or source identity.
    public func coordinateImage<A: ExactScalarAdmission & ~Copyable>(to target: borrowing OriginalParameterFrame<Source,F>,
        permutation: [Int],gains: [F.Value],offsets: [F.Value],limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> Self {
        let target = copy target
        return try OriginalDomainAccess.run(&admission) { a in
            try frame.require(limits,&a); try target.require(limits,&a)
            let n = arity
            guard target.arity == n,permutation.count == n,gains.count == n,offsets.count == n else { throw OriginalDomainIdentityFailure.invalidDomain }
            try OriginalDomainAccess.storage(n,Bool.self,&a)
            var seen = [Bool](repeating:false,count:n)
            try OriginalDomainAccess.storage(n,ExactParameterSet<F>.self,&a)
            var axes: [ExactParameterSet<F>] = []; axes.reserveCapacity(n)
            let t = DefaultOriginalParameterTransporter<Source,F>()
            for i in 0..<n {
                try a.consumeWork(1); let j = permutation[i]
                guard j >= 0,j < n,!seen[j] else { throw OriginalDomainIdentityFailure.invalidDomain }; seen[j] = true
                guard frame.coordinateSemantics[j] == target.coordinateSemantics[i] else { throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics }
                axes.append(try t.image(storage[j],gain:gains[i],offset:offsets[i],domain:target.owner.domains[i],field:target.owner.field,&a))
            }
            return try .init(frame:target,axes:axes,using:&a)
        }
    }

    /// Coordinate ownership is independent of equality of the selected sets.
    public func sharesFrame(with other: borrowing Self) -> Bool { frame.owner === other.frame.owner }

    public func contains<A: ExactScalarAdmission & ~Copyable>(_ tuple: borrowing [F.Value],
        limits: OriginalDomainIdentityLimits, using admission: inout A) throws(OriginalDomainIdentityFailure) -> Bool {
        let input = copy tuple
        return try OriginalDomainAccess.run(&admission) { a in
            try frame.require(limits,&a)
            return try DefaultOriginalParameterTransporter<Source,F>().contains(input,self,&a)
        }
    }

    public func contains<A: ExactScalarAdmission & ~Copyable>(_ tuple: borrowing [F.Value],
        queryField: F, limits: OriginalDomainIdentityLimits, using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> Bool {
        let input = copy tuple
        return try OriginalDomainAccess.run(&admission) { a in
            try frame.require(limits, &a)
            _ = try queryField.sign(of: frame.scalarField.integer(1, using: &a), using: &a)
            guard input.count == arity else { throw OriginalDomainIdentityFailure.invalidDomain }
            var included = true
            for i in input.indices {
                try a.consumeWork(1)
                if try !frame.owner.domains[i].contains(input[i], in: storage[i], queryField: queryField, using: &a) {
                    included = false
                }
            }
            return included
        }
    }

    public func intersection<A: ExactScalarAdmission & ~Copyable>(_ other: borrowing Self,
        limits: OriginalDomainIdentityLimits, using admission: inout A) throws(OriginalDomainIdentityFailure) -> Self {
        let rhs = copy other
        return try OriginalDomainAccess.run(&admission) { a in
            try frame.require(limits,&a); try rhs.frame.require(limits,&a)
            guard sharesFrame(with:rhs) else { throw OriginalDomainIdentityFailure.foreignOwner }
            try OriginalDomainAccess.storage(arity,ExactParameterSet<F>.self,&a)
            var axes: [ExactParameterSet<F>] = []; axes.reserveCapacity(arity)
            for i in 0..<arity {
                try a.consumeWork(1)
                axes.append(try frame.owner.domains[i].intersection(storage[i],rhs.storage[i],using:&a))
            }
            return try .init(frame:frame,axes:axes,using:&a)
        }
    }

    /// Disjoint Cartesian strips partition the entire difference, including boundaries.
    public func difference<A: ExactScalarAdmission & ~Copyable>(_ other: borrowing Self,
        limits: OriginalDomainIdentityLimits, using admission: inout A) throws(OriginalDomainIdentityFailure) -> [Self] {
        let rhs = copy other
        return try OriginalDomainAccess.run(&admission) { a in
            try frame.require(limits,&a); try rhs.frame.require(limits,&a)
            guard sharesFrame(with:rhs) else { throw OriginalDomainIdentityFailure.foreignOwner }
            if isEmpty { return [] }
            if rhs.isEmpty {
                guard limits.maximumCharts > 0 else { throw OriginalDomainIdentityFailure.chartLimit }
                try OriginalDomainAccess.storage(1,Self.self,&a); return [self]
            }
            let overlap = try intersection(rhs,limits:limits,using:&a)
            if overlap.isEmpty {
                guard limits.maximumCharts > 0 else { throw OriginalDomainIdentityFailure.chartLimit }
                try OriginalDomainAccess.storage(1,Self.self,&a); return [self]
            }
            var pieces: [Self] = []
            for cut in 0..<arity {
                try a.consumeWork(1)
                let outside = try frame.owner.domains[cut].difference(storage[cut],rhs.storage[cut],using:&a)
                if outside.isEmpty { continue }
                guard pieces.count < limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
                try OriginalDomainAccess.storage(arity,ExactParameterSet<F>.self,&a)
                var axes: [ExactParameterSet<F>] = []; axes.reserveCapacity(arity)
                for i in 0..<arity {
                    try a.consumeWork(1)
                    axes.append(i < cut ? overlap.storage[i] : i == cut ? outside : storage[i])
                }
                try OriginalDomainAccess.storage(1,Self.self,&a)
                pieces.append(try .init(frame:frame,axes:axes,using:&a))
            }
            return pieces
        }
    }

    public func equals<A: ExactScalarAdmission & ~Copyable>(_ other: borrowing Self,
        limits: OriginalDomainIdentityLimits, using admission: inout A) throws(OriginalDomainIdentityFailure) -> Bool {
        let rhs = copy other
        return try OriginalDomainAccess.run(&admission) { a in
            try frame.require(limits,&a); try rhs.frame.require(limits,&a)
            guard sharesFrame(with:rhs) else { throw OriginalDomainIdentityFailure.foreignOwner }
            if isEmpty || rhs.isEmpty { return isEmpty == rhs.isEmpty }
            var same = true
            for i in 0..<arity {
                try a.consumeWork(1)
                if try !frame.owner.domains[i].setEqual(storage[i],rhs.storage[i],using:&a) { same = false }
            }
            return same
        }
    }
}
