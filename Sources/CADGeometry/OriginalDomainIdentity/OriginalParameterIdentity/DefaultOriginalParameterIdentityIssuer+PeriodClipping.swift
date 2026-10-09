#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

extension DefaultOriginalParameterIdentityIssuer {
    func periodicIdentity<A: ExactScalarAdmission & ~Copyable>(effective: OriginalParameterSelection<S,F>,
        selected: OriginalParameterSelection<S,F>,period: OriginalSourcePeriodReceipt<S,F>,cycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits,_ a: inout A) throws -> OriginalParameterIdentity<S,F> {
        let left = try effective.intersection(selected,limits:limits,using:&a)
        let t = DefaultOriginalParameterTransporter<S,F>(),f = left.frame.scalarField,n = left.arity
        let whole = try ExactParameterInterval<F.Value>.checked(field:f,lower:.negativeInfinity,upper:.positiveInfinity,
            depth:.init(value:0,coefficient:0),using:&a)
        try OriginalDomainAccess.storage(n,[ExactParameterInterval<F.Value>].self,&a)
        try OriginalDomainAccess.storage(n,ExactParameterInterval<F.Value>.self,&a)
        try OriginalDomainAccess.storage(n,OriginalCoordinateSemantics.self,&a)
        let bridge = try t.frame(source:effective.frame.source,field:f,support:Array(repeating:[whole],count:n),
            semantics:Array(left.frame.coordinateSemantics),limits:limits,using:&a)
        // Clip in the unbounded bridge before admitting a translated image into bounded authored support.
        let lift = try t.periodicLift(from:left,to:bridge,period:period,cycle:cycle,limits:limits,using:&a)
        try OriginalDomainAccess.storage(n,Int.self,&a)
        try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,2),F.Value.self,&a)
        let one = try f.integer(1,using:&a),zero = try f.integer(0,using:&a)
        let originalInBridge = try t.affine(from:effective,to:bridge,permutation:Array(0..<n),
            gains:Array(repeating:one,count:n),offsets:Array(repeating:zero,count:n),limits:limits,using:&a)
        let right = try lift.transport.image.intersection(originalInBridge.image,limits:limits,using:&a)
        let reverse = try t.inverse(lift.transport,limits:limits,using:&a)
        let restricted = try t.restrict(reverse,to:right,limits:limits,using:&a)
        let mapped = try t.inverse(restricted,limits:limits,using:&a)
        let map = try t.reframed(mapped,to:effective.frame,limits:limits,using:&a)
        try OriginalDomainAccess.storage(1,OriginalSourcePeriodReceipt<S,F>.self,&a)
        return try make(kind:.periodicOrbit,left:map.local,right:map.image,
            permutation:map.permutation,gains:map.gains,offsets:map.offsets,periods:[period],
            depth:map.depth,using:&a,limits:limits)
    }
}
