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
    nonisolated static func interval(_ lo:Int,_ hi:Int,_ f:Base,_ a:inout ExactScalarLedger,
        denominator:Int = 1,upper:Bool = true) throws -> ExactParameterInterval<Base.Value> {
        try .checked(field:f,lower:.finite(f.dividing(f.integer(lo,using:&a),f.integer(denominator,using:&a),using:&a)),
            upper:.finite(f.dividing(f.integer(hi,using:&a),f.integer(denominator,using:&a),using:&a)),
            includesLower:true,includesUpper:upper,depth:.zero,using:&a)
    }
    nonisolated static func prepare(_ a:inout ExactScalarLedger) throws -> (Raw,Identity) {
        let l=try Common.limits(),f=try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
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
            .issue(source:source,child:childCover,requested:[[interval(1,1,f,&a)],[interval(0,1,f,&a)]],limits:l,using:&a)
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
            try require(try r.equals(g.parameterTransport.numerators[i],uv[i],using:&a))
            try require(try r.equals(g.parameterTransport.denominators[i],one,using:&a))
        }
        let raw=try DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.surfaceSurface,first:family,second:family,
            maximumPairs:1,limits:l,cellLimits:Common.cellLimits(),topologyLimits:Common.topologyLimits(),using:&a)
        return (raw,identity)
    }
    nonisolated static func query<A:ExactScalarAdmission & ~Copyable>(_ raw:Raw,_ identity:Identity,_ a:inout A) throws -> Result {
        try DefaultOriginalIssuedGraphSelfContactQuery<Source,Evidence,Cover,Evidence,Cover>().contacts(in:raw,
            excluding:[identity],domainLimits:Common.limits(),cellLimits:Common.cellLimits(),topologyLimits:Common.topologyLimits(),using:&a)
    }
    nonisolated static func oracle(_ result:Result,_ a:inout ExactScalarLedger) throws {
        try require(result.raw.pairs.count==1 && result.refinements.count==1 && result.identities.count==1 && result.authoredDiagonals.count==1)
        let raw=result.raw.pairs[0].relation.projection.original,refined=result.refinements[0].pullback
        try require(refined.coordinateMap==[0,1,2,3] && refined.source.cells.count==raw.cells.count)
        for i in raw.cells.indices { try require(refined.source.cells[i]==raw.cells[i]) }
        var totals:[Int]=[]
        for isRefined in [false,true] {
            let partition=isRefined ? refined.region.partition:raw.partition
            let c=try ExactRealCellDomain<Base>(retaining:partition.source,using:&a),r=c.polynomials,f=try c.coefficientField(of:partition.source,using:&a)
            let x=try r.variable(0,using:&a),y=try r.variable(1,using:&a),s=try r.variable(2,using:&a),t=try r.variable(3,using:&a)
            var laws=[y,t]
            if isRefined {
                let half=try r.constant(f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a),using:&a)
                laws += [try r.subtracting(x,s,using:&a),try r.subtracting(x,half,using:&a),try r.subtracting(s,half,using:&a)]
            }
            let proofs=try laws.map { law -> ExactRealCellSignInvariant<Base> in
                guard let p=try c.signInvariant(for:law,in:partition,using:&a) else { throw Failure.assertion(#line) };return p
            }
            var terminal=0,included=0
            for cell in partition.cells where cell.axis==3 {
                terminal+=1;let signs=try proofs.map { try c.sign(of:$0,at:cell,using:&a) }
                var expected=signs[0] == .zero && signs[1] == .zero
                if isRefined { expected = expected && signs[2] != .zero && (signs[3] != .negative || signs[4] != .negative) }
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
        Common.marker("PASS complete image singular terminal iff in original parent UV")
    }
    static func main() {
        do {
            var a=try Common.ledger();let (raw,identity)=try prepare(&a)
            var q=try Common.ledger();let result=try query(raw,identity,&q)
            Common.metric("METRIC image query work/storage",[q.work,q.storageBytes])
            var independent=try Common.ledger();try oracle(result,&independent)
        } catch {
#if !hasFeature(Embedded)
            print("OBSERVED STOP S-IMAGE-COLLAPSED-OPEN-01",error)
#else
            Common.marker("OBSERVED STOP S-IMAGE-COLLAPSED-OPEN-01")
#endif
            fflush(nil);exit(2)
        }
    }
}
