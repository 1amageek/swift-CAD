#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalAnalyticDomainIssuer<S: OriginalAnalyticCoordinateReading,F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalAnalyticDomainIssuing {
    public typealias Source = S
    public typealias Field = F
    public init() {}
    func intervals<A: ExactScalarAdmission & ~Copyable>(_ law: borrowing OriginalAnalyticCoordinateLawReceipt<S,F>,
        field: F,using a: inout A) throws -> [[ExactParameterInterval<F.Value>]] {
        try OriginalDomainAccess.storage(law.axes.count,[ExactParameterInterval<F.Value>].self,&a)
        try OriginalDomainAccess.storage(law.axes.count,ExactParameterInterval<F.Value>.self,&a)
        var axes: [[ExactParameterInterval<F.Value>]] = []
        for axis in law.axes {
            try a.consumeWork(1)
            let lower: ExactParameterBound<F.Value> = axis.lower.map { .finite($0) } ?? .negativeInfinity
            let upper: ExactParameterBound<F.Value> = axis.upper.map { .finite($0) } ?? .positiveInfinity
            axes.append([try .checked(field:field,lower:lower,upper:upper,depth:.init(value:0,coefficient:0),using:&a)])
        }
        return axes
    }
    public func frame<A: ExactScalarAdmission & ~Copyable>(law: borrowing OriginalAnalyticCoordinateLawReceipt<S,F>,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<S,F> {
        let law = copy law
        return try OriginalDomainAccess.run(&admission) { a in
            try law.admitProof(limits:limits.source,using:&a)
            let axes = try intervals(law,field:law.field,using:&a)
            try OriginalDomainAccess.storage(law.axes.count,OriginalCoordinateSemantics.self,&a)
            var semantics: [OriginalCoordinateSemantics] = []
            for axis in law.axes { try a.consumeWork(1); semantics.append(axis.meaning) }
            return try DefaultOriginalParameterTransporter<S,F>().frame(source:law.source,field:law.field,support:axes,semantics:semantics,limits:limits,using:&a)
        }
    }
    public func issue<A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<S,F>,law: borrowing OriginalAnalyticCoordinateLawReceipt<S,F>,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalAnalyticDomainCover<S,F> {
        let r = copy request,law = copy law
        return try OriginalDomainAccess.run(&admission) { a in
            guard limits.maximumFamilies >= law.periods.count else { throw OriginalDomainIdentityFailure.familyLimit }
            guard try r.frame.source.owns(law.source.chart(0,limits:limits.source,using:&a)) else { throw OriginalDomainIdentityFailure.foreignOwner }
            guard r.arity == law.axes.count else { throw OriginalDomainIdentityFailure.invalidDomain }
            try law.admitProof(limits:limits.source,using:&a)
            for i in 0..<r.arity { try a.consumeWork(1); guard r.frame.coordinateSemantics[i] == law.axes[i].meaning else { throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics } }
            let support = try r.frame.selection(intervals:intervals(law,field:r.frame.scalarField,using:&a),limits:limits,using:&a)
            guard try support.equals(r.frame.fullSelection(limits:limits,using:&a),limits:limits,using:&a) else { throw OriginalDomainIdentityFailure.invalidDomain }
            let effective = try r.intersection(support,limits:limits,using:&a)
            try OriginalDomainAccess.storage(1,OriginalAnalyticDomainCover<S,F>.self,&a)
            return .init(law:law,support:support,request:r,effective:effective)
        }
    }
}
