#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

extension DefaultOriginalParameterIdentityIssuer: OriginalAnalyticParameterIdentityIssuing
where S: OriginalAnalyticCoordinateReading, F: ExactScalarImporting {
    public func periodic<A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalAnalyticDomainCover<S,F>,
        from selected: borrowing OriginalParameterSelection<S,F>,axis: Int,cycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,F> {
        let cover = copy cover,selected = copy selected
        return try OriginalDomainAccess.run(&admission) { a in
            guard cover.integerFamilyRank <= limits.maximumFamilies else { throw OriginalDomainIdentityFailure.familyLimit }
            try cover.law.admitProof(limits:limits.source,using:&a)
            var period: OriginalSourcePeriodReceipt<S,F>? = nil
            for candidate in cover.law.periods {
                try a.consumeWork(1); if candidate.axis == axis { period = candidate }
            }
            guard let period else { throw OriginalDomainIdentityFailure.unsupportedSourceProof }
            let left = try cover.effective.intersection(selected,limits:limits,using:&a)
            let t = DefaultOriginalParameterTransporter<S,F>(),f = left.frame.scalarField,n = left.arity
            let whole = try ExactParameterInterval<F.Value>.checked(field:f,lower:.negativeInfinity,upper:.positiveInfinity,
                depth:.init(value:0,coefficient:0),using:&a)
            try OriginalDomainAccess.storage(n,[ExactParameterInterval<F.Value>].self,&a)
            try OriginalDomainAccess.storage(n,ExactParameterInterval<F.Value>.self,&a)
            try OriginalDomainAccess.storage(n,OriginalCoordinateSemantics.self,&a)
            let bridge = try t.frame(source:cover.source,field:f,support:Array(repeating:[whole],count:n),
                semantics:Array(left.frame.coordinateSemantics),limits:limits,using:&a)
            // Clip in the unbounded bridge before admitting a translated image into bounded authored support.
            let lift = try t.periodicLift(from:left,to:bridge,period:period,cycle:cycle,limits:limits,using:&a)
            try OriginalDomainAccess.storage(n,Int.self,&a)
            try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,2),F.Value.self,&a)
            let one = try f.integer(1,using:&a),zero = try f.integer(0,using:&a)
            let originalInBridge = try t.affine(from:cover.effective,to:bridge,permutation:Array(0..<n),
                gains:Array(repeating:one,count:n),offsets:Array(repeating:zero,count:n),limits:limits,using:&a)
            let right = try lift.transport.image.intersection(originalInBridge.image,limits:limits,using:&a)
            let reverse = try t.inverse(lift.transport,limits:limits,using:&a)
            let restricted = try t.restrict(reverse,to:right,limits:limits,using:&a)
            let mapped = try t.inverse(restricted,limits:limits,using:&a)
            let map = try t.reframed(mapped,to:cover.effective.frame,limits:limits,using:&a)
            try OriginalDomainAccess.storage(1,OriginalSourcePeriodReceipt<S,F>.self,&a)
            return try make(kind:.periodicOrbit,left:map.local,right:map.image,
                permutation:map.permutation,gains:map.gains,offsets:map.offsets,periods:[period],
                depth:map.depth,using:&a,limits:limits)
        }
    }
    public func collapsed<A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalAnalyticDomainCover<S,F>,
        on selected: borrowing OriginalParameterSelection<S,F>,fiber: Int,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,F> {
        let cover = copy cover,selected = copy selected
        return try OriginalDomainAccess.run(&admission) { a in
            try cover.law.admitProof(limits:limits.source,using:&a)
            guard fiber >= 0,fiber < cover.law.collapsedFibers.count else { throw OriginalDomainIdentityFailure.unsupportedSourceProof }
            let theorem = cover.law.collapsedFibers[fiber]
            let scope = try cover.effective.intersection(selected,limits:limits,using:&a)
            guard scope.arity == 2,!scope.isEmpty,theorem.fixedAxis != theorem.varyingAxis,
                scope.axes.indices.contains(theorem.fixedAxis),scope.axes.indices.contains(theorem.varyingAxis),
                scope.frame.source.owns(theorem.anchor) else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
            let f = scope.frame.scalarField
            for interval in scope.axes[theorem.fixedAxis].intervals {
                try a.consumeWork(1)
                guard case .finite(let lo) = interval.lower,case .finite(let hi) = interval.upper,
                    try f.compare(lo,theorem.fixedValue,using:&a) == .equal,
                    try f.compare(hi,theorem.fixedValue,using:&a) == .equal else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
            }
            try OriginalDomainAccess.storage(1,OriginalSourceCollapsedFiberReceipt<S,F>.self,&a)
            return try make(kind:.collapsedSubset,left:scope,right:scope,permutation:nil,gains:[],offsets:[],
                laws:cover.law.position,fibers:[theorem],using:&a,limits:limits)
        }
    }
}
