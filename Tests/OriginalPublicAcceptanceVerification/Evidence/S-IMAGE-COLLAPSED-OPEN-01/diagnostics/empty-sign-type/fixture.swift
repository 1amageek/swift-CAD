import CADCore
@testable import CADGeometry
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif

/// Actual swapped/reversed parent with a transported half-open child collapse.
@main struct ImageCollapsedOpenAcceptance {
    typealias Common = NativeIdentityCompositionAcceptance
    typealias Base = OriginalExactScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Source = OriginalParameterImageSnapshot<OriginalImageSurface3D,BSplineSurface3D>
    typealias Selection = OriginalParameterImageChartSelection<BSplineSurface3D,OriginalBSplineChartSelection,Base>
    typealias Cover = OriginalIssuedDomainCover<Source,Selection,Base>
    typealias Evidence = OriginalRationalChartReceipt<Source,Selection,Base>
    typealias Raw = OriginalIssuedGraphRelations<Source,Evidence,Cover,Source,Evidence,Cover>
    typealias Result = OriginalIssuedGraphSelfContacts<Source,Evidence,Cover,Evidence,Cover>
    typealias Identity = OriginalParameterIdentity<Source,Base>
    enum Failure: Error { case assertion(Int), unexpectedSuccess }
    nonisolated static func require(_ value:Bool,_ line:Int = #line) throws {
        guard value else { Common.metric("FAIL S-IMAGE-COLLAPSED-OPEN-01",[line]);throw Failure.assertion(line) }
    }
    nonisolated static func limits(depth:Int = 16,count:Int = 64,sourceDepth:Int = 1) throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:sourceDepth),maximumTransportDepth:depth,maximumCharts:64,maximumFamilies:2,maximumIdentityProofs:count)
    }
    nonisolated static func interval(_ lo:Int,_ hi:Int,_ f:Base,_ a:inout ExactScalarLedger,
        denominator:Int = 1,upper:Bool = true) throws -> ExactParameterInterval<Base.Value> {
        try .checked(field:f,lower:.finite(f.dividing(f.integer(lo,using:&a),f.integer(denominator,using:&a),using:&a)),
            upper:.finite(f.dividing(f.integer(hi,using:&a),f.integer(denominator,using:&a),using:&a)),
            includesLower:true,includesUpper:upper,depth:.zero,using:&a)
    }
    nonisolated static func prepare(_ a:inout ExactScalarLedger,empty:Bool = false,field:Base? = nil) throws -> (Raw,Identity) {
        let l=try limits(),f=try field ?? Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let surface=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[[.init(x:0,y:0,z:0),.init(x:0,y:0,z:0)],[.init(x:0,y:1,z:0),.init(x:1,y:1,z:0)]])
        let image=try OriginalImageSurface3D(source:.bSpline(surface),uGain:-1,vGain:1,uOffset:1,
            transform:.init(basisX:.unitX,basisY:.unitY,basisZ:.unitZ,translation:.zero),swapAxes:true,tolerance:.standard)
        let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalParameterImageSurfaceSnapshotProvider(
            child:OriginalNativeSurfaceFamilySnapshotProvider(tolerance:.standard),tolerance:.standard))
            .bind(image,limits:l.source,using:&a)
        let child=source.original.originalChild,issuer=DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,Base>()
        let space=try issuer.prepare(source:child,field:f,limits:l,using:&a)
        let childCover=try issuer.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
        let childLaw=try DefaultOriginalBSplineChartIssuer<BSplineSurface3D,Base>().issue(source:child,
            chart:space.sourceCharts[0],field:f,limits:l.source,using:&a)
        let scope=try space.frame.selection(intervals:[[interval(0,1,f,&a,denominator:2,upper:false)],[interval(0,0,f,&a)]],limits:l,using:&a)
        let childIdentity=try DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,Base>().collapsed(law:childLaw,on:scope,limits:l,using:&a)
        let affine=try DefaultOriginalParameterImageDomainIssuer<Source,OriginalBSplineDomainCover<BSplineSurface3D,Base>>()
            .issue(source:source,child:childCover,requested:[[interval(1,1,f,&a)],[interval(0,empty ? 0:1,f,&a)]],limits:l,using:&a)
        let identity=try DefaultOriginalAffineChildParameterIdentityIssuer<Source,OriginalBSplineDomainCover<BSplineSurface3D,Base>>()
            .lifted(childIdentity,through:affine,limits:l,using:&a)
        let laws=try DefaultOriginalFiniteParameterImageChartPreparer<Source,OriginalBSplineChartSelection,Base>()
            .prepare(source:source,children:[childLaw],field:f,maximumCharts:1,limits:l.source,using:&a)
        let cover=try DefaultOriginalIssuedDomainBinder().bind(laws:laws,request:affine.effective,limits:l,using:&a)
        let algebraic=try Field.base(field:f,maximumExtensionLevel:32,using:&a)
        let family=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover,field:algebraic,maximumGraphs:1,limits:l,using:&a)
        try require(family.graphs.count==1 && child.sourceDepth==0 && source.sourceDepth==1)
        // Local coordinates remain original child (a,b); parent UV is (1-b,a).
        let g=family.graphs[0].original.graph,r=g.polynomials
        let x=try r.variable(0,using:&a),y=try r.variable(1,using:&a),zero=try r.zero(using:&a),one=try r.constant(f.integer(1,using:&a),using:&a)
        let position=[try r.multiplying(x,y,using:&a),y,zero,one]
        let uv=[try r.subtracting(one,y,using:&a),x]
        for i in 0..<4 { try require(try r.equals(g.homogeneous[i],position[i],using:&a)) }
        for i in 0..<2 {
            try require(try r.equals(g.parameterTransport.numerators[i],r.multiplying(uv[i],g.parameterTransport.denominators[i],using:&a),using:&a))
            try require(try r.equals(g.parameterTransport.denominators[i],r.constant(f.integer(i==0 ? -1:1,using:&a),using:&a),using:&a))
        }
        let raw=try DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.surfaceSurface,first:family,second:family,
            maximumPairs:1,limits:l,cellLimits:Common.cellLimits(),topologyLimits:Common.topologyLimits(),using:&a)
        return (raw,identity)
    }
    nonisolated static func query<A:ExactScalarAdmission & ~Copyable>(_ raw:Raw,_ identity:Identity,_ a:inout A) throws -> Result {
        try DefaultOriginalIssuedGraphSelfContactQuery<Source,Evidence,Cover,Evidence,Cover>().contacts(in:raw,
            excluding:[identity],domainLimits:limits(),cellLimits:Common.cellLimits(),topologyLimits:Common.topologyLimits(),using:&a)
    }
    nonisolated static func oracle(_ result:Result,_ a:inout ExactScalarLedger,empty:Bool = false) throws {
        try require(result.raw.pairs.count==1 && result.refinements.count==1 && result.identities.count==1 && result.authoredDiagonals.count==1)
        let raw=result.raw.pairs[0].relation.projection.original,refined=result.refinements[0].pullback
        try require(refined.coordinateMap==[0,1,2,3] && refined.source.cells.count==raw.cells.count)
        for i in raw.cells.indices { try require(refined.source.cells[i]==raw.cells[i]) }
        var totals:[Int]=[]
        for isRefined in [false,true] {
            let partition=isRefined ? refined.region.partition:raw.partition
            let c=try ExactRealCellDomain<Base>(retaining:partition.source,using:&a),r=c.polynomials,f=try c.coefficientField(of:partition.source,using:&a)
            let x=try r.variable(0,using:&a),y=try r.variable(1,using:&a),s=try r.variable(2,using:&a),t=try r.variable(3,using:&a)
            var laws=empty ? [x,y,s,t]:[y,t]
            if isRefined && !empty {
                let half=try r.constant(f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a),using:&a)
                laws += [try r.subtracting(x,s,using:&a),try r.subtracting(x,half,using:&a),try r.subtracting(s,half,using:&a)]
            }
            let proofs=try laws.enumerated().map { index,law -> ExactRealCellSignInvariant<Base>? in
                if let p=try c.signInvariant(for:law,in:partition,using:&a) { return p }
                guard empty else { throw Failure.assertion(#line) }
                let domain=partition.source.domains[index]
                guard case .finite(let lo)=domain.lower,case .finite(let hi)=domain.upper else { throw Failure.assertion(#line) }
                try require(domain.includesLower && domain.includesUpper && f.sign(of:lo,using:&a) == .zero && f.sign(of:hi,using:&a) == .zero)
                return nil
            }
            var terminal=0,included=0
            for cell in partition.cells where cell.axis==3 {
                terminal+=1;let signs=try proofs.map { proof -> RobustSign in
                    if let proof { return try c.sign(of:proof,at:cell,using:&a) };return .zero
                }
                var expected=empty ? signs.allSatisfy { $0 == .zero }:signs[0] == .zero && signs[1] == .zero
                if empty && isRefined { expected=false }
                if isRefined && !empty { expected = expected && signs[2] != .zero && (signs[3] != .negative || signs[4] != .negative) }
                if isRefined {
                    guard let i=refined.region.cells.firstIndex(of:cell) else { throw Failure.assertion(#line) }
                    try require(refined.region.included[i]==expected)
                    try require(expected ? raw.cells.indices.contains(refined.sourceCellOrdinals[i]):refined.sourceCellOrdinals[i] == -1)
                } else { try require(raw.cells.contains(cell)==expected) }
                if expected { included+=1;try require(cell.dimension<=2) }
            }
            totals += [terminal,included]
        }
        Common.metric("METRIC image raw/refined terminal/included",totals)
        if empty {
            try require(totals[1]==1 && totals[3]==0)
            Common.marker("PASS complete image empty singleton requested product")
        } else {
            try require(totals[1]==9 && totals[3]==20)
            Common.marker("PASS complete image singular terminal iff in original parent UV")
        }
    }
    nonisolated static func controls() throws {
        let (result,n,bytes,calls)=try retained();Common.metric("METRIC preparedQueryBoundary",[n,bytes,calls])
        var a=try Common.ledger();let f=result.raw.first.source.original.originalChild.original
        var changed=f;changed.controlPoints[0][0].x=7
        try require(result.raw.first.source.original.originalChild.original.controlPoints[0][0].x==0)
        let base=result.raw.first.coverage.coverage.request.frame.scalarField
        let field=result.raw.first.field,ids=DefaultOriginalParameterIdentityIssuer<Source,Base>(),identity=result.identities[0]
        let view=try ids.relation(of:identity,limits:limits(depth:2,count:2),using:&a)
        try require(view.depth==2 && view.proofCount==2 && view.evidenceSourceDepth==1 && view.kind == .collapsedSubset)
        guard case .completeProduct=view.constraints else { throw Failure.assertion(#line) }
        for i in 0...4 { for j in 0...4 {
            let x=try base.dividing(base.integer(i,using:&a),base.integer(4,using:&a),using:&a)
            let y=try base.dividing(base.integer(j,using:&a),base.integer(4,using:&a),using:&a)
            let zero=try base.integer(0,using:&a),one=try base.integer(1,using:&a)
            try require(try ids.decide(identity,left:[one,x],right:[one,y],limits:limits(),using:&a) == (i<2 && j<2 ? .proven:.notEstablished))
            let tuple=try [x,zero,y,zero].map { try field.importingBase($0,using:&a) }
            try require(try result.contains(pairOrdinal:0,liftedCoordinates:tuple,domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&a) == (i != j && (i>=2 || j>=2)))
        } }
        for l in [try limits(depth:1),try limits(count:1),try limits(sourceDepth:0)] {
            do { _=try ids.relation(of:identity,limits:l,using:&a);throw Failure.unexpectedSuccess }
            catch OriginalDomainIdentityFailure.transportDepthLimit {} catch OriginalDomainIdentityFailure.identityLimit {} catch OriginalDomainIdentityFailure.sourceDepthLimit {}
        }
        var foreignAdmission=try Common.ledger();let (_,foreign)=try prepare(&foreignAdmission,field:base)
        do { _=try query(result.raw,foreign,&a);throw Failure.unexpectedSuccess }
        catch NativeExactRelationFailure.domain(.foreignOwner) {}
        var cancelled=try Common.ledger();cancelled.cancel()
        do { _=try result.contains(pairOrdinal:0,liftedCoordinates:[],domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&cancelled);throw Failure.unexpectedSuccess }
        catch NativeExactRelationFailure.scalar(.cancelled) {}
        Common.marker("PASS image swapped open scope both directions, owner/depth/count/source refusal and detached COW lifetime")
    }
    nonisolated static func retained() throws -> (Result,Int,Int,Int) {
        var a=try Common.ledger();let (raw,identity)=try prepare(&a)
        var q=try Common.PublicationAdmission();let result=try query(raw,identity,&q)
        return (result,q.ledger.work,q.ledger.storageBytes,q.storageCalls)
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
                Common.marker("PASS complete image empty final-publication cancellation");return
            }
            var q=try Common.ledger();let result=try query(raw,identity,&q)
            Common.metric("METRIC image query work/storage",[q.work,q.storageBytes])
            var independent=try Common.ledger();try oracle(result,&independent);return
        }
        try require(parts.count==4)
        guard let n=Int(parts[1]),let bytes=Int(parts[2]),let calls=Int(parts[3]) else { throw Failure.assertion(#line) }
        if group=="cancel" {
            var entry=try Common.ledger();entry.cancel()
            do { _=try query(raw,identity,&entry);throw Failure.unexpectedSuccess } catch NativeExactRelationFailure.scalar(.cancelled) {}
            var final=try Common.PublicationAdmission(cancellingCall:calls)
            do { _=try query(raw,identity,&final);throw Failure.unexpectedSuccess } catch NativeExactRelationFailure.scalar(.cancelled) {}
            try require(final.storageCalls==calls && final.ledger.work==n && final.ledger.storageBytes==bytes)
            Common.marker("PASS image entry and final-publication cancellation");return
        }
        var q=ExactScalarLedger(limits:try .init(work:group=="work" ? n-1:n,storageBytes:group=="storage" ? bytes-1:bytes,valueDepth:32,coefficientDepth:32))
        if group=="exact" {
            let result=try query(raw,identity,&q);try require(q.work==n && q.storageBytes==bytes)
            var independent=try Common.ledger();try oracle(result,&independent);Common.marker("PASS image exact query workN/storageN");return
        }
        do { _=try query(raw,identity,&q);throw Failure.unexpectedSuccess }
        catch let failure as NativeExactRelationFailure {
            switch (group,failure) {
            case ("work",.scalar(.resourceLimit(.work))),("work",.domain(.scalar(.resourceLimit(.work)))),
                ("storage",.scalar(.resourceLimit(.storage))),("storage",.domain(.scalar(.resourceLimit(.storage)))):break
            default:throw failure
            }
        }
        Common.marker(group=="work" ? "PASS image workN-1 typed refusal":"PASS image storageN-1 typed refusal")
    }
    static func main() {
        do { try run() } catch {
#if !hasFeature(Embedded)
            print("OBSERVED STOP S-IMAGE-COLLAPSED-OPEN-01",error)
#else
            Common.marker("OBSERVED STOP S-IMAGE-COLLAPSED-OPEN-01")
#endif
            fflush(nil);exit(2)
        }
    }
}
