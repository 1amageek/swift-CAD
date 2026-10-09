import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
@testable import SourceIssuer
import IssuedGraphs

public enum GraphFixtures {
    enum Failure:Error { case incorrect(Int) }
    typealias Base=OriginalExactScalarDomain
    typealias Field=ExactAlgebraicScalarDomain<Base>
    typealias Law=OriginalRationalChartReceipt<NativeSnapshot,OriginalBSplineChartSelection,Base>
    typealias Cover=OriginalIssuedDomainCover<NativeSnapshot,OriginalBSplineChartSelection,Base>
    struct Offset:OriginalOffsetSourceReading { let originalChild:OriginalSourceBinding<NativeSnapshot>;let originalDistance:Double }
    struct OffsetProvider:OriginalSourceSnapshotting {
        func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing Offset,limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure)->OriginalSourceSnapshot<Offset> {
            do {try a.checkpoint();try a.consumeWork(1);return .init(original:copy input,sourceDepth:input.originalChild.sourceDepth+1)} catch {throw .init(preserving:error)}
        }
    }
    static func require(_ condition:Bool,line:Int = #line) throws { if !condition {throw Failure.incorrect(line)} }
    static func ledger(work:Int=80_000_000,storage:Int=700_000_000,depth:Int=32) throws -> ExactScalarLedger {
        .init(limits:try .init(work:work,storageBytes:storage,valueDepth:depth,coefficientDepth:depth))
    }
    static func limits(depth:Int=1,charts:Int=8) throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:depth),maximumTransportDepth:8,maximumCharts:charts,maximumFamilies:8,maximumIdentityProofs:8)
    }
    static func interval<A:ExactScalarAdmission & ~Copyable>(_ f:Base,_ low:Double,_ high:Double,_ a:inout A,closed:Bool=true) throws -> ExactParameterInterval<OriginalExactScalar> {
        try .checked(field:f,lower:.finite(f.binary64(exactly:low,using:&a)),upper:.finite(f.binary64(exactly:high,using:&a)),includesLower:true,includesUpper:closed,depth:.init(value:0,coefficient:0),using:&a)
    }
    static func native<A:ExactScalarAdmission & ~Copyable>(_ input:NativeInput,_ f:Base,_ a:inout A) throws -> OriginalFiniteBSplineCharts<NativeSnapshot> {
        let source=try DefaultOriginalSourceBindingIssuer(provider:NativeProvider()).bind(input,limits:limits().source,using:&a)
        return try DefaultOriginalFiniteBSplineChartPreparer<NativeSnapshot>().prepare(source:source,field:f,maximumCharts:8,limits:limits().source,using:&a)
    }
    static func cover<A:ExactScalarAdmission & ~Copyable>(_ charts:OriginalFiniteBSplineCharts<NativeSnapshot>,_ a:inout A,selection:[[ExactParameterInterval<OriginalExactScalar>]]? = nil) throws -> Cover {
        let f=charts.field,l=try limits()
        var support:[[ExactParameterInterval<OriginalExactScalar>]]=[]
        for bound in charts.support {support.append([try .checked(field:f,lower:.finite(bound.lower),upper:.finite(bound.upper),depth:.init(value:0,coefficient:0),using:&a)])}
        let frame=try DefaultOriginalParameterTransporter<NativeSnapshot,Base>().frame(source:charts.source,field:f,support:support,semantics:[OriginalCoordinateSemantics](repeating:.authoredScalar,count:charts.support.count),limits:l,using:&a)
        let request=try selection.map {try frame.selection(intervals:$0,limits:l,using:&a)} ?? frame.fullSelection(limits:l,using:&a)
        return try DefaultOriginalIssuedDomainBinder().bind(laws:charts.laws,request:request,limits:l,using:&a)
    }
    static func curve()->NativeInput { .init(degrees:[1],knots:[[0,0,1,1]],counts:[2],controls:[[0.5,0.5,-0.25],[0.5,0.5,0.75]],weights:[1,1],periodic:[false]) }
    static func plane(knot:Bool=false)->NativeInput {
        knot ? .init(degrees:[1,1],knots:[[0,0,0.5,1,1],[0,0,1,1]],counts:[3,2],controls:[[0,0,0],[0.5,0,0],[1,0,0],[0,1,0],[0.5,1,0],[1,1,0]],weights:[1,1,1,1,1,1],periodic:[false,false])
            : .init(degrees:[1,1],knots:[[0,0,1,1],[0,0,1,1]],counts:[2,2],controls:[[0,0,0],[1,0,0],[0,1,0],[1,1,0]],weights:[1,1,1,1],periodic:[false,false])
    }
    static func contains(_ selection:ExactRealCellSelection<Base>,_ tuple:[Double],_ a:inout ExactScalarLedger) throws -> Bool {
        let cells=try ExactRealCellDomain<Base>(retaining:selection.partition.source,using:&a),f=try cells.coefficientField(of:selection.partition.source,using:&a)
        var coordinates:[Field.Value]=[]
        for value in tuple {coordinates.append(try f.binary64(exactly:value,using:&a))}
        let point=try cells.point(field:f,coordinates:coordinates,using:&a)
        guard let cell=try cells.locate(point,in:selection.partition,limits:.init(maximumRoots:100),using:&a) else {return false}
        return selection.cells.contains(cell)
    }
    static func cellLimits() throws -> ExactRealCellLimits {try .init(maximumStoredCells:20_000,maximumRootsPerStack:100)}
    static func topologyLimits() throws -> ExactRealTopologyLimits {try .init(maximumGeneratedCells:20_000,maximumRootsPerStack:100,maximumClosures:1000,maximumAttachmentPieces:20_000,maximumComponents:1000)}
    public static func run(_ mode:Int) throws {
        switch mode {case 0:try rational();case 1:try offset(false);case 2:try offset(true);case 3:try correspondence();case 4:try failures();case 5:try surfaceAndSingular();default:throw Failure.incorrect(#line)}
        print("PASS B3 source/DI/L5 group=\(mode)")
    }
    static func rational() throws {
        var a=try ledger();let f=try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a),field=try Field.base(field:f,maximumExtensionLevel:32,using:&a),l=try limits()
        let first=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover(native(curve(),f,&a),&a),field:field,maximumGraphs:8,limits:l,using:&a)
        let charts=try native(plane(),f,&a)
        for mode in 0..<4 {
            let selection:[[ExactParameterInterval<OriginalExactScalar>]]?
            switch mode {
            case 1:selection=[[try interval(f,0.5,0.5,&a)],[try interval(f,0.5,0.5,&a)]]
            case 2:selection=[[try interval(f,0,0.5,&a,closed:false)],[try interval(f,0,1,&a)]]
            case 3:selection=[[try interval(f,0,0.25,&a),try interval(f,0.75,1,&a)],[try interval(f,0,1,&a)]]
            default:selection=nil
            }
            let second=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover(charts,&a,selection:selection),field:field,maximumGraphs:8,limits:l,using:&a)
            let result=try DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.curveSurface,first:first,second:second,maximumPairs:8,limits:l,cellLimits:cellLimits(),topologyLimits:topologyLimits(),using:&a)
            try require(result.pairs.count==1)
            let relation=result.pairs[0].relation
            try require(contains(relation.selection,[0.25,0.5,0.5],&a)==(mode<2))
            try require(!contains(relation.selection,[0.5,0.5,0.5],&a))
            try require(relation.components.count==(mode<2 ? 1:0))
            try result.admitProof(limits:l,using:&a)
        }
        print("MEASURE rational work=\(a.work) storage=\(a.storageBytes)")
    }
    static func offset(_ knot:Bool) throws {
        var a=try ledger();let f=try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a),field=try Field.base(field:f,maximumExtensionLevel:32,using:&a),l=try limits()
        let first=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover(native(curve(),f,&a),&a),field:field,maximumGraphs:8,limits:l,using:&a)
        let child=try native(plane(knot:knot),f,&a)
        let source=try DefaultOriginalSourceBindingIssuer(provider:OffsetProvider()).bind(Offset(originalChild:child.source,originalDistance:0.25),limits:l.source,using:&a)
        let family=try DefaultOriginalFiniteNativeOffsetLawPreparer<Offset>().prepare(source:source,child:child,maximumCharts:8,limits:l.source,using:&a)
        let issuer=DefaultOriginalNativeOffsetDomainIssuer<Offset>(),frame=try issuer.frame(family:family,limits:l,using:&a)
        let cover=try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
        let second=try DefaultOriginalOffsetGraphFamilyPreparer().prepare(cover:cover,field:field,maximumGraphs:8,limits:l,using:&a)
        let result=try DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.curveSurface,first:first,second:second,maximumPairs:8,limits:l,cellLimits:cellLimits(),topologyLimits:topologyLimits(),using:&a)
        try require(result.pairs.count==(knot ? 2:1))
        for pair in result.pairs {
            let expected = !knot || pair.secondGraphIndex==1
            try require(contains(pair.relation.selection,[0.5,0.5,0.5],&a)==expected)
            try require(!contains(pair.relation.selection,[0.25,0.5,0.5],&a))
            if expected {
                try require(pair.relation.selection.cells.count==1 && pair.relation.selection.cells[0].dimension==0)
                try require(pair.relation.projection.liftedCells(forProjectedOrdinal:0)!.count==1)
                let lift=pair.relation.projection.original
                try require(contains(lift,[0.5,0.5,0.5,1],&a))
                try require(!contains(lift,[0.5,0.5,0.5,-1],&a))
            } else {try require(pair.relation.selection.cells.isEmpty)}
        }
        try require(result.second.coverage.family.source.original.originalDistance==0.25)
        // Complete empty selection retains the guarded cover and source depth.
        let outside=try interval(f,2,3,&a)
        let emptyCover=try issuer.issue(request:frame.selection(intervals:[[outside],[outside]],limits:l,using:&a),family:family,limits:l,using:&a)
        let empty=try DefaultOriginalOffsetGraphFamilyPreparer().prepare(cover:emptyCover,field:field,maximumGraphs:0,limits:l,using:&a)
        let excluded=try DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.curveSurface,first:first,second:empty,maximumPairs:0,limits:l,cellLimits:cellLimits(),topologyLimits:topologyLimits(),using:&a)
        try require(excluded.pairs.isEmpty && excluded.second.coverage.effectiveEnclosure.isEmpty)
        do {try excluded.admitProof(limits:limits(depth:0),using:&a);throw Failure.incorrect(#line)} catch NativeExactRelationFailure.domain(.sourceDepthLimit) {}
        print("MEASURE offset knot=\(knot) work=\(a.work) storage=\(a.storageBytes)")
    }
    static func nonlinear(_ a:inout ExactScalarLedger) throws -> OriginalDomainBoundParametricGraph<NativeSnapshot,Base,Law> {
        let f=try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a),l=try limits()
        let input=NativeInput(degrees:[1],knots:[[0,0,1,1]],counts:[2],controls:[[0,0,0],[1,0,0]],weights:[1,1],periodic:[false])
        let native=try native(input,f,&a),source=native.source,ring=native.laws[0].polynomials
        let s=try ring.variable(0,using:&a),square=try ring.multiplying(s,s,using:&a),zero=try ring.zero(using:&a),one=try ring.constant(f.integer(1,using:&a),using:&a)
        // Test-only certified double cover of C(tau)=(tau,0,0), tau=s*s.
        // Both numerator and denominator are negative; production issuers are unchanged.
        let law=try Law(chart:native.laws[0].chart,field:f,polynomials:ring,homogeneous:[square,zero,zero,one],support:[.init(lower:f.integer(-1,using:&a),upper:f.integer(1,using:&a))],parameterTransport:.init(numerators:[ring.negated(square,using:&a)],denominators:[ring.negated(one,using:&a)]),proofDepth:.init(value:20,coefficient:20))
        let graph=try DefaultOriginalRationalGraphIssuer().issue(law,limits:l.source,using:&a)
        let frame=try DefaultOriginalParameterTransporter<NativeSnapshot,Base>().frame(source:source,field:f,support:[[interval(f,0,1,&a)]],semantics:[.authoredScalar],limits:l,using:&a)
        let request=try frame.selection(intervals:[[.checked(field:f,lower:.finite(f.binary64(exactly:0.25,using:&a)),upper:.finite(f.integer(1,using:&a)),includesLower:false,includesUpper:true,depth:.init(value:0,coefficient:0),using:&a)]],limits:l,using:&a)
        return try DefaultOriginalParametricGraphDomainBinder().bind(graph:graph,request:request,limits:l,using:&a)
    }
    static func correspondence() throws {
        var a=try ledger();let binding=try nonlinear(&a),field=try Field.base(field:binding.graph.field,maximumExtensionLevel:32,using:&a)
        let prepared=try DefaultOriginalIssuedGraphCompiler().compile(binding:binding,field:field,limits:limits(),using:&a)
        let cells=try ExactRealCellDomain<Base>(retaining:prepared.graph.predicate.source,using:&a)
        let partition=try cells.decompose(prepared.graph.predicate.source,limits:cellLimits(),using:&a)
        let selection=try cells.select(partition,matching:prepared.graph.predicate,using:&a)
        for s in [-1.0,-0.75,-0.5,0,0.5,0.75,1] {try require(contains(selection,[s],&a)==(abs(s)>0.5))}
        try require(prepared.depth.value>=20 && prepared.depth.coefficient>=20)
        var low=try ledger(depth:19)
        do {try prepared.admitProof(limits:limits(),using:&low);throw Failure.incorrect(#line)} catch NativeExactRelationFailure.domain(.scalar(.resourceLimit(.valueDepth))) {}
        print("PASS forward nonlinear/negative-denominator pullback and retained depth")
    }
    static func surfaceAndSingular() throws {
        var a=try ledger();let f=try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a),field=try Field.base(field:f,maximumExtensionLevel:32,using:&a),l=try limits()
        let first=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover(native(plane(),f,&a),&a),field:field,maximumGraphs:8,limits:l,using:&a)
        let vertical=NativeInput(degrees:[1,1],knots:[[0,0,1,1],[0,0,1,1]],counts:[2,2],controls:[[0,0.5,-0.5],[1,0.5,-0.5],[0,0.5,0.5],[1,0.5,0.5]],weights:[1,1,1,1],periodic:[false,false])
        let second=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover(native(vertical,f,&a),&a),field:field,maximumGraphs:8,limits:l,using:&a)
        let result=try DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.surfaceSurface,first:first,second:second,maximumPairs:8,limits:l,cellLimits:cellLimits(),topologyLimits:topologyLimits(),using:&a)
        try require(result.pairs.count==1 && result.pairs[0].relation.components.count==1)
        try require(contains(result.pairs[0].relation.selection,[0.25,0.5,0.25,0.5],&a))
        try require(contains(result.pairs[0].relation.selection,[0,0.5,0,0.5],&a))
        try require(!contains(result.pairs[0].relation.selection,[0.25,0.5,0.5,0.5],&a))
        try require(result.pairs[0].relation.selection.cells.contains(where:{$0.dimension==1}))
        // A valid collapsed Native surface has no regular offset positions.
        // Its identically zero normal guard must remain false after folding.
        var collapsed=plane();collapsed.controls=[[Double]](repeating:[0,0,0],count:4)
        let child=try native(collapsed,f,&a)
        let source=try DefaultOriginalSourceBindingIssuer(provider:OffsetProvider()).bind(Offset(originalChild:child.source,originalDistance:0.25),limits:l.source,using:&a)
        let family=try DefaultOriginalFiniteNativeOffsetLawPreparer<Offset>().prepare(source:source,child:child,maximumCharts:8,limits:l.source,using:&a)
        let issuer=DefaultOriginalNativeOffsetDomainIssuer<Offset>(),frame=try issuer.frame(family:family,limits:l,using:&a)
        let selected=try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
        let prepared=try DefaultOriginalOffsetGraphFamilyPreparer().prepare(cover:selected,field:field,maximumGraphs:8,limits:l,using:&a)
        let graph=prepared.graphs[0].graph,cells=try ExactRealCellDomain<Base>(retaining:graph.predicate.source,using:&a)
        let partition=try cells.decompose(graph.predicate.source,limits:cellLimits(),using:&a)
        try require(cells.select(partition,matching:graph.predicate,using:&a).cells.isEmpty)
        print("PASS source/DI/L5 SSI curve and singular-offset exclusion")
    }
    static func failures() throws {
        var setup=try ledger();let binding=try nonlinear(&setup),foreign=try nonlinear(&setup),field=try Field.base(field:binding.graph.field,maximumExtensionLevel:32,using:&setup),l=try limits(),compiler=DefaultOriginalIssuedGraphCompiler<NativeSnapshot,Law>()
        do {_=try DefaultOriginalParametricGraphDomainBinder().bind(graph:binding.graph,request:foreign.request,limits:l,using:&setup);throw Failure.incorrect(#line)} catch OriginalDomainIdentityFailure.foreignOwner {}
        var measured=try ledger();let retained=try compiler.compile(binding:binding,field:field,limits:l,using:&measured)
        var exact=try ledger(work:measured.work,storage:measured.storageBytes)
        _=try compiler.compile(binding:binding,field:field,limits:l,using:&exact)
        for resource in [ExactResource.work,.storage] {
            var short=try ledger(work:resource == .work ? measured.work-1:measured.work,storage:resource == .storage ? measured.storageBytes-1:measured.storageBytes)
            do {_=try compiler.compile(binding:binding,field:field,limits:l,using:&short);throw Failure.incorrect(#line)}
            catch let failure as NativeExactRelationFailure {
                switch failure {
                case .scalar(.resourceLimit(let r)),.relation(.scalar(.resourceLimit(let r))),.domain(.scalar(.resourceLimit(let r))),.cell(.scalar(.resourceLimit(let r))),.relation(.cell(.scalar(.resourceLimit(let r)))):try require(r==resource)
                default:throw failure
                }
            }
        }
        var cancelled=try ledger();cancelled.cancel()
        do {_=try compiler.compile(binding:binding,field:field,limits:l,using:&cancelled);throw Failure.incorrect(#line)} catch NativeExactRelationFailure.scalar(.cancelled) {}
        var baseline=try CheckpointAdmission();_=try compiler.compile(binding:binding,field:field,limits:l,using:&baseline)
        var terminal=try CheckpointAdmission(stop:baseline.checkpoints)
        do {_=try compiler.compile(binding:binding,field:field,limits:l,using:&terminal);throw Failure.incorrect(#line)} catch NativeExactRelationFailure.scalar(.cancelled) {}
        try retained.admitProof(limits:l,using:&setup)
        try require(retained.original.graph.source.original.coordinate(ofControl:1,in:0)==1)
        let f=binding.graph.field
        let c=try cover(native(curve(),f,&setup),&setup)
        do {_=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:c,field:field,maximumGraphs:0,limits:l,using:&setup);throw Failure.incorrect(#line)} catch NativeExactRelationFailure.domain(.chartLimit) {}
        let first=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:c,field:field,maximumGraphs:8,limits:l,using:&setup)
        let second=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover(native(plane(),f,&setup),&setup),field:field,maximumGraphs:8,limits:l,using:&setup)
        do {_=try DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.curveSurface,first:first,second:second,maximumPairs:0,limits:l,cellLimits:cellLimits(),topologyLimits:topologyLimits(),using:&setup);throw Failure.incorrect(#line)} catch NativeExactRelationFailure.domain(.chartLimit) {}
        // An empty request must retain the deeper enclosing frame proof.
        let nativeCurve=try native(curve(),f,&setup)
        let deepSupport=try ExactParameterInterval<OriginalExactScalar>.checked(field:f,lower:.finite(f.integer(0,using:&setup)),upper:.finite(f.integer(1,using:&setup)),depth:.init(value:25,coefficient:25),using:&setup)
        let deepFrame=try DefaultOriginalParameterTransporter<NativeSnapshot,Base>().frame(source:nativeCurve.source,field:f,support:[[deepSupport]],semantics:[.authoredScalar],limits:l,using:&setup)
        let outside=try interval(f,2,3,&setup)
        let emptyCover=try DefaultOriginalIssuedDomainBinder().bind(laws:nativeCurve.laws,request:deepFrame.selection(intervals:[[outside]],limits:l,using:&setup),limits:l,using:&setup)
        let empty=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:emptyCover,field:field,maximumGraphs:0,limits:l,using:&setup)
        try require(empty.graphs.isEmpty && empty.depth.value>=25 && empty.depth.coefficient>=25)
        var shallow=try ledger(depth:24)
        do {try empty.admitProof(limits:l,using:&shallow);throw Failure.incorrect(#line)} catch NativeExactRelationFailure.scalar(.resourceLimit(.valueDepth)) {}
        print("PASS graph binding/compiler ownership, exact work/storage caps, inherited depth, entry/terminal cancellation and graph/pair caps")
    }
}
