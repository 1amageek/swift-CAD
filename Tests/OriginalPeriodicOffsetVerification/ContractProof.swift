import L0
import L1
import DI0
import SourceIssuer
import DI

@main struct PeriodicOffsetContractProof {
    static func prepare(_ base: PeriodicOffsetFixtures.Family,_ a: inout ExactScalarLedger) throws -> PeriodicOffsetFixtures.Cover {
        let l=try TransportFixtures.limits(charts:32)
        let child=try DefaultOriginalBSplineFundamentalChartPreparer<NativeSnapshot>().prepare(source:base.child.source,
            field:base.field,maximumCharts:32,limits:l.source,using:&a)
        let family=try DefaultOriginalPeriodicNativeOffsetLawPreparer<OffsetDomainFixtures.Source>().prepare(source:base.source,
            child:child,maximumCharts:32,limits:l.source,using:&a)
        return try PeriodicOffsetFixtures.cover(family,&a)
    }
    static func resource(_ error: any Error,_ expected: ExactResource) throws {
        switch error {
        case ExactScalarFailure.resourceLimit(let r),OriginalSourceIssuanceFailure.scalar(.resourceLimit(let r)),
            OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(let r))),
            OriginalDomainIdentityFailure.scalar(.resourceLimit(let r)),
            OriginalDomainIdentityFailure.domain(.scalar(.resourceLimit(let r))),
            OriginalDomainIdentityFailure.source(.scalar(.resourceLimit(let r))),
            OriginalDomainIdentityFailure.source(.polynomial(.scalar(.resourceLimit(let r)))):
            try TransportFixtures.require(r==expected)
        default:throw error
        }
    }
    static func main() throws {
        let base=try PeriodicOffsetFixtures.family(twoAxes:true),l=try TransportFixtures.limits(charts:32)
        var measured=try TransportFixtures.admission();_=try prepare(base,&measured)
        var exact=try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes)
        let c=try prepare(base,&exact)
        for r in [ExactResource.work,.storage] {
            var short=try TransportFixtures.admission(work:measured.work-(r == .work ? 1:0),storage:measured.storageBytes-(r == .storage ? 1:0))
            do { _=try prepare(base,&short);throw ExactScalarFailure.invalidEvidence }
            catch { try resource(error,r) }
        }
        var a=try TransportFixtures.admission()
        let foreign=try PeriodicOffsetFixtures.family(twoAxes:true)
        do {
            _=try DefaultOriginalPeriodicNativeOffsetLawPreparer<OffsetDomainFixtures.Source>().prepare(source:base.source,
                child:foreign.child,maximumCharts:32,limits:l.source,using:&a)
            throw ExactScalarFailure.invalidEvidence
        } catch OriginalSourceIssuanceFailure.foreignBinding {}
        do {
            _=try DefaultOriginalPeriodicNativeOffsetLawPreparer<OffsetDomainFixtures.Source>().prepare(source:base.source,
                child:base.child,maximumCharts:8,limits:l.source,using:&a)
            throw ExactScalarFailure.invalidEvidence
        } catch OriginalSourceIssuanceFailure.chartLimit {}
        let f=base.field,half=try f.binary64(exactly:0.5,using:&a)
        let foreignScalar=try foreign.field.integer(1,using:&a)
        for empty in [false,true] {
            let current: PeriodicOffsetFixtures.Cover
            if empty {
                let request=try c.space.frame.selection(intervals:[[],[]],limits:l,using:&a)
                current=try DefaultOriginalPeriodicNativeOffsetDomainIssuer<OffsetDomainFixtures.Source>().issue(space:c.space,
                    request:request,limits:l,using:&a)
            } else { current=c }
            for tuple in [[foreignScalar,half],[half,foreignScalar]] {
                do { _=try current.positionIncidents(at:tuple,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
                catch OriginalDomainIdentityFailure.scalar(.incompatibleDomain) {}
            }
            do { _=try current.liftedPositionIncidents(at:[half,half,foreignScalar],limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
            catch OriginalDomainIdentityFailure.scalar(.incompatibleDomain) {}
        }
        do { _=try c.positionIncidents(at:[half,half],limits:TransportFixtures.limits(sourceDepth:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.source(.sourceDepthLimit) {}
        do { _=try c.positionIncidents(at:[half,half],limits:TransportFixtures.limits(depth:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.transportDepthLimit {}
        let q=ExactRationalScalarDomain(),zero=try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
        for cycles in [[],[zero],[zero,zero,zero]] {
            do { _=try c.member(template:0,cycles:cycles,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
            catch OriginalDomainIdentityFailure.invalidDomain {}
        }
        for index in [-1,9] {
            do { _=try c.member(template:index,cycles:[zero,zero],limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
            catch OriginalDomainIdentityFailure.invalidDomain {}
        }
        print("PASS full preparation exact work/storage and one-less, source/chart/transport authority, all-coordinate/empty foreign fields and invalid cycles/templates")
        print("Preparation admitted work \(measured.work), bytes \(measured.storageBytes)")
    }
}
