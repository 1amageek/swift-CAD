import CADCore
@testable import CADGeometry
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif

/// Full singular original parameter product with a half-open positional identity scope.
@main struct NativeCollapsedOpenAcceptance {
    typealias Common = NativeIdentityCompositionAcceptance
    typealias Base = ExactRationalScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Cells = ExactRealCellDomain<Base>
    typealias Raw = NativeExactParametricRelations<BSplineSurface3D,BSplineSurface3D>
    typealias Identity = OriginalParameterIdentity<BSplineSurface3D,Field>
    typealias Result = OriginalExactNativeSelfContacts
    enum Failure: Error { case assertion(Int), unexpectedSuccess }
    nonisolated static func require(_ value:Bool,_ line:Int = #line) throws {
        guard value else { Common.metric("FAIL S-NATIVE-COLLAPSED-OPEN-SCOPE-01",[line]);throw Failure.assertion(line) }
    }
    nonisolated static func limits() throws -> OriginalDomainIdentityLimits { try Common.limits() }
    nonisolated static func interval(_ lo:Int,_ hi:Int,_ f:Field,_ a:inout ExactScalarLedger,
        denominator:Int = 1,upper:Bool = true) throws -> ExactParameterInterval<Field.Value> {
        try .checked(field:f,lower:.finite(f.dividing(f.integer(lo,using:&a),f.integer(denominator,using:&a),using:&a)),
            upper:.finite(f.dividing(f.integer(hi,using:&a),f.integer(denominator,using:&a),using:&a)),
            includesLower:true,includesUpper:upper,depth:.init(value:0,coefficient:0),using:&a)
    }
    nonisolated static func prepare(_ a:inout ExactScalarLedger,empty:Bool = false) throws -> (Raw,Identity) {
        let f=try Field.base(field:Base(),maximumExtensionLevel:10,using:&a),l=try limits()
        let surface=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[[.init(x:0,y:0,z:0),.init(x:0,y:0,z:0)],[.init(x:0,y:1,z:0),.init(x:1,y:1,z:0)]])
        let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplineSurfaceSnapshotProvider(tolerance:.standard))
            .bind(surface,limits:l.source,using:&a)
        let issuer=DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,Field>()
        let space=try issuer.prepare(source:source,field:f,limits:l,using:&a)
        let request=try space.frame.selection(intervals:[[interval(0,empty ? 0:1,f,&a)],[interval(0,0,f,&a)]],limits:l,using:&a)
        let cover=try issuer.issue(space:space,request:request,limits:l,using:&a)
        let raw=try DefaultSurfaceSurfaceIntersector().exactParameterRelations(first:cover,second:cover,domainLimits:l,
            maximumMaps:64,maximumPairs:4096,cellLimits:Common.cellLimits(),topologyLimits:Common.topologyLimits(),using:&a)
        try require(raw.pieces.count==1)
        let law=raw.pieces[0].first.law,r=law.polynomials,u=try r.variable(0,using:&a),v=try r.variable(1,using:&a)
        let expected=[try r.multiplying(u,v,using:&a),v,try r.zero(using:&a),try r.constant(f.integer(1,using:&a),using:&a)]
        for i in 0..<4 { try require(try r.equals(law.homogeneous[i],expected[i],using:&a)) }
        let scope=try space.frame.selection(intervals:[[interval(0,1,f,&a,denominator:2,upper:false)],[interval(0,0,f,&a)]],limits:l,using:&a)
        let identity=try DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,Field>().collapsed(law:law,on:scope,limits:l,using:&a)
        return (raw,identity)
    }
    nonisolated static func query<A:ExactScalarAdmission & ~Copyable>(_ raw:Raw,_ identity:Identity,_ a:inout A) throws -> Result {
        try DefaultOriginalExactNativeSelfContactQuery().contacts(in:raw,excluding:[identity],domainLimits:limits(),
            cellLimits:Common.cellLimits(),topologyLimits:Common.topologyLimits(),using:&a)
    }
    nonisolated static func invariants(_ p:ExactRealCellPartition<Base>,refined:Bool,_ a:inout ExactScalarLedger)
        throws -> (Cells,[ExactRealCellSignInvariant<Base>]) {
        let c=try Cells(retaining:p.source,using:&a),r=c.polynomials,f=try c.coefficientField(of:p.source,using:&a)
        let u=try r.variable(0,using:&a),v=try r.variable(1,using:&a),s=try r.variable(2,using:&a),w=try r.variable(3,using:&a)
        var laws=[v,w]
        if refined {
            let half=try r.constant(f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a),using:&a)
            laws.append(try r.subtracting(u,s,using:&a));laws.append(try r.subtracting(u,half,using:&a));laws.append(try r.subtracting(s,half,using:&a))
        }
        var proofs:[ExactRealCellSignInvariant<Base>]=[]
        for law in laws {
            guard let proof=try c.signInvariant(for:law,in:p,using:&a) else { throw Failure.assertion(#line) }
            proofs.append(proof)
        }
        return (c,proofs)
    }
    nonisolated static func oracle(_ result:Result,_ a:inout ExactScalarLedger,empty:Bool = false) throws {
        let raw=result.raw,piece=raw.pieces[0],selected=piece.relation.selection
        try require(raw.pieces.count==1 && result.refinements.count==1 && result.identities.count==2)
        let identity=result.identities[1],ids=DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,Field>()
        let view=try ids.relation(of:identity,limits:limits(),using:&a)
        try require(view.kind == .collapsedSubset)
        guard case .completeProduct=view.constraints else { throw Failure.assertion(#line) }
        if empty {
            let f=raw.first.space.frame.scalarField
            for partition in [selected.partition,result.refinements[0].pullback.region.partition] {
                try require(partition.source.domains.count==4)
                for domain in partition.source.domains {
                    guard case .finite(let lo)=domain.lower,case .finite(let hi)=domain.upper else { throw Failure.assertion(#line) }
                    try require(domain.includesLower && domain.includesUpper && f.sign(of:lo,using:&a) == .zero && f.sign(of:hi,using:&a) == .zero)
                }
                try require(partition.cells.filter { $0.axis==3 }.count==1)
            }
            try require(selected.cells.count==1 && selected.cells[0].dimension==0)
            let pb=result.refinements[0].pullback,region=pb.region
            try require(pb.coordinateMap==[0,1,2,3] && pb.source.cells.count==selected.cells.count)
            for i in selected.cells.indices { try require(pb.source.cells[i]==selected.cells[i]) }
            try require(region.cells.count==1 && region.cells[0].dimension==0 && region.included==[false] && pb.sourceCellOrdinals==[-1])
            Common.marker("PASS complete empty singleton requested product");return
        }
        let (c,proofs)=try invariants(selected.partition,refined:false,&a)
        var rawCount=0,rawDimension = -1
        for cell in selected.partition.cells where cell.axis==3 {
            let signs=try proofs.map { try c.sign(of:$0,at:cell,using:&a) }
            let expected=signs[0] == .zero && signs[1] == .zero
            try require(selected.cells.contains(cell)==expected)
            if expected { rawCount+=1;rawDimension=max(rawDimension,cell.dimension) }
        }
        try require(rawCount==selected.cells.count && rawDimension==(empty ? 0:2))
        let pb=result.refinements[0].pullback,region=pb.region
        try require(pb.coordinateMap==[0,1,2,3] && pb.source.cells.count==selected.cells.count)
        for i in selected.cells.indices { try require(pb.source.cells[i]==selected.cells[i]) }
        try require(region.cells.count==region.included.count && region.cells.count==pb.sourceCellOrdinals.count)
        let (rc,rp)=try invariants(region.partition,refined:true,&a)
        var checked=0,included=0,dimension = -1
        for cell in region.partition.cells where cell.axis==3 {
            let indices=region.cells.indices.filter { region.cells[$0]==cell };try require(indices.count==1)
            let i=indices[0],signs=try rp.map { try rc.sign(of:$0,at:cell,using:&a) }
            let expected=signs[0] == .zero && signs[1] == .zero && signs[2] != .zero && (signs[3] != .negative || signs[4] != .negative)
            try require(region.included[i]==expected)
            let ordinal=pb.sourceCellOrdinals[i];try require(expected ? selected.cells.indices.contains(ordinal):ordinal == -1)
            if expected { included+=1;dimension=max(dimension,cell.dimension) };checked+=1
        }
        try require(checked==region.cells.count && (empty ? included==0:included>0 && dimension==2))
        Common.metric("METRIC raw/refined/included/work/bytes",[rawCount,checked,included,a.work,a.storageBytes])
        Common.marker(empty ? "PASS complete empty singleton requested product" : "PASS complete singular terminal iff: u!=uPrime AND(u>=1/2 OR uPrime>=1/2)")
    }
    nonisolated static func retained() throws -> (Result,Int,Int,Int) {
        var a=try Common.ledger();let (raw,identity)=try prepare(&a)
        var q=try Common.PublicationAdmission();let result=try query(raw,identity,&q)
        return (result,q.ledger.work,q.ledger.storageBytes,q.storageCalls)
    }
    nonisolated static func controls() throws {
        let (result,n,bytes,calls)=try retained();Common.metric("METRIC preparedQueryBoundary",[n,bytes,calls])
        var a=try Common.ledger();let f=result.raw.first.space.frame.scalarField,identity=result.identities[1]
        let ids=DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,Field>()
        for i in 0...4 { for j in 0...4 {
            let u=try f.dividing(f.integer(i,using:&a),f.integer(4,using:&a),using:&a),s=try f.dividing(f.integer(j,using:&a),f.integer(4,using:&a),using:&a),zero=try f.integer(0,using:&a)
            try require(try result.contains(firstTuple:[u,zero],secondTuple:[s,zero],domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&a)==(i != j && (i>=2 || j>=2)))
            let decision=try ids.decide(identity,left:[u,zero],right:[s,zero],limits:limits(),using:&a)
            try require((decision == .proven)==(i<2 && j<2))
        } }
        let admitted=try ids.relation(of:identity,limits:Common.limits(depth:1,count:1),using:&a)
        try require(admitted.depth==1 && admitted.proofCount==1 && !admitted.left.axes[0].intervals.first!.includesUpper)
        for mode in 0..<2 {
            do { _=try ids.relation(of:identity,limits:Common.limits(depth:mode==0 ? 0:1,count:mode==1 ? 0:1),using:&a);throw Failure.unexpectedSuccess }
            catch let failure as OriginalDomainIdentityFailure {
                switch (mode,failure) { case (0,.transportDepthLimit),(1,.identityLimit):break;default:throw failure }
            }
        }
        var cancelled=try Common.ledger();cancelled.cancel();let zero=try f.integer(0,using:&a)
        do { _=try result.contains(firstTuple:[zero,zero],secondTuple:[zero,zero],domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&cancelled);throw Failure.unexpectedSuccess }
        catch NativeExactRelationFailure.scalar(.cancelled) {}
        var copy=result.raw.first.source.original;copy.controlPoints[0][0].x=7
        try require(result.raw.first.source.original.controlPoints[0][0].x==0)
        let law=result.raw.pieces[0].first.law,frame=result.raw.first.space.frame
        let noncollapsed=try frame.fullSelection(limits:limits(),using:&a)
        do { _=try ids.collapsed(law:law,on:noncollapsed,limits:limits(),using:&a);throw Failure.unexpectedSuccess }
        catch OriginalDomainIdentityFailure.invalidIdentityProof {}
        let foreignSource=try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplineSurfaceSnapshotProvider(tolerance:.standard)).bind(result.raw.first.source.original,limits:limits().source,using:&a)
        let foreign=try DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,Field>().prepare(source:foreignSource,field:f,limits:limits(),using:&a)
        do { _=try ids.collapsed(law:law,on:foreign.frame.fullSelection(limits:limits(),using:&a),limits:limits(),using:&a);throw Failure.unexpectedSuccess }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        Common.marker("PASS open half boundary both directions, nonconstant/foreign scope refusal and detached lifetime")
    }
    nonisolated static func run() throws {
        let argument:String
        if let pointer=getenv("CAD_PROOF_GROUP") { argument=String(cString:pointer) } else { argument="complete" }
        let parts=argument.split(separator:":"),group=String(parts[0])
        if group=="controls" { try controls();return }
        var a=try Common.ledger();let (raw,identity)=try prepare(&a,empty:group=="empty")
        if group=="complete" || group=="empty" {
            if group=="empty" {
                var calibration=try Common.PublicationAdmission();let result=try query(raw,identity,&calibration)
                var oracleAdmission=try Common.ledger();try oracle(result,&oracleAdmission,empty:true)
                var final=try Common.PublicationAdmission(cancellingCall:calibration.storageCalls)
                do { _=try query(raw,identity,&final);throw Failure.unexpectedSuccess } catch NativeExactRelationFailure.scalar(.cancelled) {}
                try require(final.storageCalls==calibration.storageCalls && final.ledger.work==calibration.ledger.work && final.ledger.storageBytes==calibration.ledger.storageBytes)
                Common.marker("PASS complete empty final-publication cancellation");return
            }
            let result=try query(raw,identity,&a);var oracleAdmission=try Common.ledger();try oracle(result,&oracleAdmission);return
        }
        try require(parts.count==4)
        guard let n=Int(parts[1]),let bytes=Int(parts[2]),let calls=Int(parts[3]) else { throw Failure.assertion(#line) }
        if group=="cancel" {
            var entry=try Common.ledger();entry.cancel()
            do { _=try query(raw,identity,&entry);throw Failure.unexpectedSuccess } catch NativeExactRelationFailure.scalar(.cancelled) {}
            var final=try Common.PublicationAdmission(cancellingCall:calls)
            do { _=try query(raw,identity,&final);throw Failure.unexpectedSuccess } catch NativeExactRelationFailure.scalar(.cancelled) {}
            try require(final.storageCalls==calls && final.ledger.work==n && final.ledger.storageBytes==bytes)
            Common.marker("PASS entry and final-publication cancellation");return
        }
        var q=ExactScalarLedger(limits:try .init(work:group=="work" ? n-1:n,storageBytes:group=="storage" ? bytes-1:bytes,valueDepth:32,coefficientDepth:32))
        if group=="exact" {
            let result=try query(raw,identity,&q);try require(q.work==n && q.storageBytes==bytes)
            var independent=try Common.ledger();try oracle(result,&independent);Common.marker("PASS exact query workN/storageN");return
        }
        do { _=try query(raw,identity,&q);throw Failure.unexpectedSuccess }
        catch let failure as NativeExactRelationFailure {
            switch (group,failure) {
            case ("work",.scalar(.resourceLimit(.work))),("work",.domain(.scalar(.resourceLimit(.work)))),
                ("storage",.scalar(.resourceLimit(.storage))),("storage",.domain(.scalar(.resourceLimit(.storage)))):break
            default:throw failure
            }
        }
        Common.marker(group=="work" ? "PASS workN-1 typed refusal":"PASS storageN-1 typed refusal")
    }
    static func main() {
        do { try run() } catch {
#if !hasFeature(Embedded)
            print("OBSERVED STOP S-NATIVE-COLLAPSED-OPEN-SCOPE-01",error)
#else
            Common.marker("OBSERVED STOP S-NATIVE-COLLAPSED-OPEN-SCOPE-01")
#endif
            fflush(nil);exit(2)
        }
    }
}
