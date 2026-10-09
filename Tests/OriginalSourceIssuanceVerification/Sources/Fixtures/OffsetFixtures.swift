import L0
import L1
import SourceIssuer

extension SourceFixtures {
    struct OffsetInput<G:Sendable>:OriginalOffsetSourceReading {
        let originalChild:OriginalSourceBinding<G>
        let originalDistance:Double
    }
    struct OffsetProvider<G:Sendable>:OriginalSourceSnapshotting {
        func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing OffsetInput<G>,
            limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OffsetInput<G>> {
            do { try a.checkpoint();try a.consumeWork(1) } catch { throw .scalar(error) }
            guard input.originalDistance.isFinite else { throw .invalidSource }
            return .init(original:copy input,sourceDepth:input.originalChild.sourceDepth+1)
        }
    }
    static func offsetInput() -> NativeInput {
        // Original P(u,v)=(u,v^2,0); the whole interior v=0 fiber is singular.
        .init(degrees:[1,2],knots:[[0,0,1,1],[-1,-1,-1,1,1,1]],counts:[2,3],
            controls:[[0,1,0],[1,1,0],[0,-1,0],[1,-1,0],[0,1,0],[1,1,0]],
            weights:[1,1,1,1,1,1],periodic:[false,false])
    }
    static func offset<A:ExactScalarAdmission & ~Copyable>(distance:Double=0.25,using a:inout A) throws -> OriginalFiniteNativeOffsetLawFamily<OffsetInput<NativeSnapshot>> {
        let limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let child=try DefaultOriginalSourceBindingIssuer(provider:NativeProvider()).bind(offsetInput(),limits:limits,using:&a)
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let charts=try DefaultOriginalFiniteBSplineChartPreparer<NativeSnapshot>().prepare(source:child,field:f,maximumCharts:1,limits:limits,using:&a)
        let source=try DefaultOriginalSourceBindingIssuer(provider:OffsetProvider<NativeSnapshot>()).bind(
            OffsetInput(originalChild:child,originalDistance:distance),limits:limits,using:&a)
        return try DefaultOriginalFiniteNativeOffsetLawPreparer<OffsetInput<NativeSnapshot>>().prepare(
            source:source,child:charts,maximumCharts:1,limits:limits,using:&a)
    }
    static func offsetKnotOwnership<A:ExactScalarAdmission & ~Copyable>(using a:inout A) throws {
        let limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let input=NativeInput(degrees:[1,1],knots:[[0,0,0.5,1,1],[0,0,1,1]],counts:[3,2],
            controls:[[0,0,0],[1,0,0],[2,0,1],[0,1,0],[1,1,0],[2,1,1]],weights:[1,1,1,1,1,1],periodic:[false,false])
        let binding=try DefaultOriginalSourceBindingIssuer(provider:NativeProvider()).bind(input,limits:limits,using:&a)
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let child=try DefaultOriginalFiniteBSplineChartPreparer<NativeSnapshot>().prepare(source:binding,field:f,maximumCharts:2,limits:limits,using:&a)
        let source=try DefaultOriginalSourceBindingIssuer(provider:OffsetProvider<NativeSnapshot>()).bind(OffsetInput(originalChild:binding,originalDistance:0.25),limits:limits,using:&a)
        let family=try DefaultOriginalFiniteNativeOffsetLawPreparer<OffsetInput<NativeSnapshot>>().prepare(source:source,child:child,maximumCharts:2,limits:limits,using:&a)
        let half=try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a)
        try require(family.laws.count==2 && !family.laws[0].ownsUpperBoundary[0] && family.laws[1].ownsUpperBoundary[0])
        try require(!family.laws[0].admitsPosition(at:[half,half],limits:limits,using:&a))
        try require(family.laws[1].admitsPosition(at:[half,half],limits:limits,using:&a))
        // Closed original child support remains intact on the nonowning differential side.
        try require(f.compare(family.laws[0].enclosingSupport[0].upper,half,using:&a) == .equal)
    }
    public static func offsetLaws() throws {
        var a=try TraceAdmission();let family=try offset(using:&a),f=family.field,law=family.laws[0]
        let limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a),half=try f.dividing(one,f.integer(2,using:&a),using:&a)
        let quarter=try f.dividing(one,f.integer(4,using:&a),using:&a),negative=try f.negated(half,using:&a)
        try require(family.laws.count==1 && family.child.laws.count==1 && law.positiveRootVariable==2)
        for (v,z) in [(half,quarter),(negative,try f.negated(quarter,using:&a))] {
            try require(law.admitsPosition(at:[half,v],limits:limits,using:&a))
            let input=[half,v,one]
            try require(law.admitsLiftedPosition(at:input,limits:limits,using:&a))
            try require(!law.admitsLiftedPosition(at:[half,v,try f.negated(one,using:&a)],limits:limits,using:&a))
            let equation=try law.polynomials.evaluated(law.positiveRootEquation,at:input,using:&a).value
            try require(f.sign(of:equation,using:&a) == .zero)
            let d=try law.polynomials.evaluated(law.denominator,at:input,using:&a).value
            let pz=try f.dividing(law.polynomials.evaluated(law.homogeneous[2],at:input,using:&a).value,d,using:&a)
            try require(f.compare(pz,z,using:&a) == .equal)
        }
        try require(!law.admitsPosition(at:[half,zero],limits:limits,using:&a))
        let noDistance=try offset(distance:0,using:&a)
        let nf=noDistance.field,nzero=try nf.integer(0,using:&a),nhalf=try nf.dividing(nf.integer(1,using:&a),nf.integer(2,using:&a),using:&a)
        try require(!noDistance.laws[0].admitsPosition(at:[nhalf,nzero],limits:limits,using:&a))
        try family.admitProof(limits:limits,using:&a)
        do { try family.admitProof(limits:.init(remainingSourceDepth:0),using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        let foreign=try offset(using:&a)
        do { _ = try DefaultOriginalFiniteNativeOffsetLawPreparer<OffsetInput<NativeSnapshot>>().prepare(source:family.source,child:foreign.child,maximumCharts:1,limits:limits,using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.foreignBinding {}
        do { _ = try DefaultOriginalFiniteNativeOffsetLawPreparer<OffsetInput<NativeSnapshot>>().prepare(source:family.source,child:family.child,maximumCharts:0,limits:limits,using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.chartLimit {}
        try offsetKnotOwnership(using:&a)
        var measured=try TraceAdmission();_ = try offset(using:&measured)
        var exact=try TraceAdmission(work:measured.work,storage:measured.storageBytes);_ = try offset(using:&exact)
        var lowWork=try TraceAdmission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try offset(using:&lowWork);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.work))) {}
        var lowStorage=try TraceAdmission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try offset(using:&lowStorage);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.storage))) {}
        var entry=try TraceAdmission();entry.base.cancel()
        do { _ = try offset(using:&entry);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.cancelled)) {}
        var final=try TraceAdmission(cancelAtStorage:measured.storageCalls)
        do { _ = try offset(using:&final);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.cancelled)) {}
        print("PASS M4 guarded Native offset exact original normal, signed branches, non-Cartesian singular fiber, sealed coverage and atomic failures")
    }
}
