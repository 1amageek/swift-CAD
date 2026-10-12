#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalRevolutionDomainIssuer<S: OriginalRevolutionSourceReading,C: Sendable,
    F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalRevolutionDomainIssuing where F.Source == F.Value {
    public typealias Source = S
    public typealias GeneratorSelection = C
    public typealias Field = F
    public init() {}
    func admitted<A: ExactScalarAdmission & ~Copyable>(_ family: OriginalFiniteRevolutionLawFamily<S,C,F>,
        limits: OriginalDomainIdentityLimits,using a: inout A) throws {
        guard limits.maximumFamilies >= 1 else { throw OriginalDomainIdentityFailure.familyLimit }
        guard family.laws.count <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
        try family.admitProof(limits:limits.source,using:&a)
    }
    func intervals<A: ExactScalarAdmission & ~Copyable>(_ family: OriginalFiniteRevolutionLawFamily<S,C,F>,using a: inout A)
        throws -> [[ExactParameterInterval<F.Value>]] {
        try OriginalDomainAccess.storage(2,[ExactParameterInterval<F.Value>].self,&a)
        try OriginalDomainAccess.storage(2,ExactParameterInterval<F.Value>.self,&a)
        var intervals: [[ExactParameterInterval<F.Value>]] = [];intervals.reserveCapacity(2)
        for axis in family.support {
            try a.consumeWork(1)
            intervals.append([try .checked(field:family.field,lower:.finite(axis.lower),upper:.finite(axis.upper),
                depth:family.proofDepth,using:&a)])
        }
        return intervals
    }
    public func frame<A: ExactScalarAdmission & ~Copyable>(family: borrowing OriginalFiniteRevolutionLawFamily<S,C,F>,
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<S,F> {
        let family = copy family
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(family,limits:limits,using:&a)
            try OriginalDomainAccess.storage(2,OriginalCoordinateSemantics.self,&a)
            return try DefaultOriginalParameterTransporter<S,F>().frame(source:family.source,field:family.field,
                support:intervals(family,using:&a),semantics:[.intrinsicAngularLabel,.authoredScalar],limits:limits,using:&a)
        }
    }
    public func issue<A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<S,F>,
        family: borrowing OriginalFiniteRevolutionLawFamily<S,C,F>,limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalRevolutionDomainCover<S,C,F> {
        let family = copy family,request = copy request
        return try OriginalDomainAccess.run(&admission) { a in
            try admitted(family,limits:limits,using:&a)
            guard request.frame.source.owns(family.period.anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
            guard request.arity == 2 else { throw OriginalDomainIdentityFailure.invalidDomain }
            guard request.frame.coordinateSemantics[0] == .intrinsicAngularLabel,
                request.frame.coordinateSemantics[1] == .authoredScalar else { throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics }
            let support = try request.frame.selection(intervals:intervals(family,using:&a),limits:limits,using:&a)
            guard try support.equals(request.frame.fullSelection(limits:limits,using:&a),limits:limits,using:&a) else { throw OriginalDomainIdentityFailure.invalidDomain }
            let effective = try support.intersection(request,limits:limits,using:&a)
            return .init(family:family,support:support,request:request,effective:effective)
        }
    }
}
