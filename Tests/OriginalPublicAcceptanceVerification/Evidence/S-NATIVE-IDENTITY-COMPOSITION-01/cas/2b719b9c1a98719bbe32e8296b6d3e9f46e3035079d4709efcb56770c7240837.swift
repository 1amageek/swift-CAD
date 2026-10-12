#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

extension DefaultOriginalParameterTransporter {
    public func periodicLift<A: ExactScalarAdmission & ~Copyable>(
        from local: borrowing OriginalParameterSelection<Source,F>, to authored: borrowing OriginalParameterFrame<Source,F>,
        period: borrowing OriginalSourcePeriodReceipt<Source,F>, cycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits, using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterPeriodicLift<Source,F> {
        let selected = copy local; let target = copy authored; let proof = copy period
        return try OriginalDomainAccess.run(&admission) { a in
            guard selected.frame.source.owns(proof.anchor), target.source.owns(proof.anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
            let axis = proof.axis, n = selected.arity
            guard axis >= 0, axis < n else { throw OriginalDomainIdentityFailure.invalidDomain }
            guard selected.frame.coordinateSemantics[axis] == proof.meaning,
                target.coordinateSemantics[axis] == proof.meaning else {
                throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics
            }
            let f = target.owner.field
            guard try f.sign(of:proof.period,using:&a) == .positive else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
            try OriginalDomainAccess.storage(n,Int.self,&a)
            try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,2),F.Value.self,&a)
            var p: [Int] = []; var gains: [F.Value] = []; var offsets: [F.Value] = []
            p.reserveCapacity(n); gains.reserveCapacity(n); offsets.reserveCapacity(n)
            let displacement = try f.multiplying(cycle.scalar(in:f,using:&a),proof.period,using:&a)
            for i in 0..<n {
                try a.consumeWork(1); p.append(i); gains.append(try f.integer(1,using:&a))
                offsets.append(i == axis ? displacement : try f.integer(0,using:&a))
            }
            let map = try affine(selected,target,p,gains,offsets,depth:1,limits:limits,using:&a)
            return .init(transport:map,period:proof,cycle:cycle)
        }
    }
}
