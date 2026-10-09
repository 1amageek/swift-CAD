import L0
import L1
import SourceIssuer

extension SourceFixtures {
    struct RevolutionInput<G:Sendable>:OriginalRevolutionSourceReading {
        let originalGenerator:OriginalSourceBinding<G>
        var originalLowerU:Double = -2*Double.pi
        var originalUpperU:Double = 2*Double.pi
        var origin:[Double] = [0,0,0]
        var direction:[Double] = [0,0,2]
        func axisOriginCoordinate(in axis:Int)->Double { origin[axis] }
        func axisDirectionCoordinate(in axis:Int)->Double { direction[axis] }
    }
    struct RevolutionProvider<G:Sendable>:OriginalSourceSnapshotting {
        func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing RevolutionInput<G>,
            limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<RevolutionInput<G>> {
            do { try a.consumeWork(1) } catch { throw .scalar(error) }
            guard input.origin.count == 3,input.direction.count == 3 else { throw .invalidSource }
            return .init(original:copy input,sourceDepth:input.originalGenerator.sourceDepth+1)
        }
    }
    typealias RevolutionReceipt=OriginalRevolutionLawReceipt<RevolutionInput<TraversalInput>,OriginalTraversalChartSelection<NativeSnapshot,OriginalBSplineChartSelection,Field>,Field>
    static func revolution<A:ExactScalarAdmission & ~Copyable>(using a:inout A) throws -> RevolutionReceipt {
        let generator=try traversalReceipt(using:&a),f=generator.field,l=try OriginalSourceIssuanceLimits(remainingSourceDepth:2)
        let source=try DefaultOriginalSourceBindingIssuer(provider:RevolutionProvider<TraversalInput>()).bind(
            RevolutionInput(originalGenerator:generator.source),limits:l,using:&a)
        return try DefaultOriginalFiniteRevolutionLawPreparer<RevolutionInput<TraversalInput>,OriginalTraversalChartSelection<NativeSnapshot,OriginalBSplineChartSelection,Field>,Field>()
            .prepare(source:source,generators:[generator],field:f,axisLength:f.integer(2,using:&a),maximumCharts:1,limits:l,using:&a).laws[0]
    }
    public static func revolutionLaws() throws {
        var a=try TraceAdmission();let result=try revolution(using:&a),f=result.field,r=result.polynomials
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
        let half=try f.dividing(one,f.integer(2,using:&a),using:&a)
        let twoThirds=try f.dividing(f.integer(2,using:&a),f.integer(3,using:&a),using:&a)
        // Original directed t=4-v; weighted generator is (2*(t-2)/(t+1),0,0).
        for (c,s,expectedX,expectedY) in [(one,zero,twoThirds,zero),(zero,one,zero,twoThirds)] {
            let input=[c,s,half],d=try r.evaluated(result.denominator,at:input,using:&a).value
            let x=try f.dividing(r.evaluated(result.homogeneous[0],at:input,using:&a).value,d,using:&a)
            let y=try f.dividing(r.evaluated(result.homogeneous[1],at:input,using:&a).value,d,using:&a)
            try require(try f.compare(x,expectedX,using:&a) == .equal)
            try require(try f.compare(y,expectedY,using:&a) == .equal)
            try require(try f.sign(of:r.evaluated(result.homogeneous[2],at:input,using:&a).value,using:&a) == .zero)
        }
        let t=try result.parameterPolynomials.evaluated(result.generatorChartParameter.numerators[0],at:[zero,half],using:&a).value
        try require(try f.compare(t,f.dividing(f.integer(7,using:&a),f.integer(2,using:&a),using:&a),using:&a) == .equal)
        try require(try f.compare(result.support[1].lower,zero,using:&a) == .equal)
        try require(try f.compare(result.support[1].upper,one,using:&a) == .equal)
        try require(try f.compare(result.period.period,f.binary64(exactly:2*Double.pi,using:&a),using:&a) == .equal)
        try require(try f.compare(result.normalizedAxis[2],one,using:&a) == .equal)
        try result.admitProof(limits:.init(remainingSourceDepth:2),using:&a)
        let issuer=DefaultOriginalRevolutionLawIssuer<RevolutionInput<TraversalInput>,OriginalTraversalChartSelection<NativeSnapshot,OriginalBSplineChartSelection,Field>,Field>()
        do { _ = try issuer.issue(source:result.source,generator:result.generator,field:f,axisLength:one,limits:.init(remainingSourceDepth:2),using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.invalidChart {}
        let foreign=try traversalReceipt(using:&a)
        do { _ = try issuer.issue(source:result.source,generator:foreign,field:f,axisLength:f.integer(2,using:&a),limits:.init(remainingSourceDepth:2),using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.foreignBinding {}
        try revolutionCoverage(using:&a)
        var measured=try TraceAdmission();_ = try revolution(using:&measured)
        var exact=try TraceAdmission(work:measured.work,storage:measured.storageBytes);_ = try revolution(using:&exact)
        var lowWork=try TraceAdmission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try revolution(using:&lowWork);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.work))) {}
        var lowStorage=try TraceAdmission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try revolution(using:&lowStorage);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.storage))) {}
        var entry=try TraceAdmission();entry.base.cancel()
        do { _ = try revolution(using:&entry);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        var final=try TraceAdmission(cancelAtStorage:measured.storageCalls)
        do { _ = try revolution(using:&final);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.cancelled)) {}
        print("PASS M4 original revolution exact weighted/reversed generator law, intrinsic period, normalized raw axis, full child support/correspondence and independent failure/cancel")
    }
    static func revolutionCoverage<A:ExactScalarAdmission & ~Copyable>(using a:inout A) throws {
        let l=try OriginalSourceIssuanceLimits(remainingSourceDepth:1),f=Field()
        let input=NativeInput(degrees:[1],knots:[[0,0,0.5,1,1]],counts:[3],controls:[[1,0,0],[2,0,0],[3,0,0]],weights:[1,2,1],periodic:[false])
        let child=try DefaultOriginalSourceBindingIssuer(provider:NativeProvider()).bind(input,limits:l,using:&a)
        var charts:[Receipt]=[]
        for span in [1,2] {
            let chart=try child.chart(OriginalBSplineChartSelection(spans:[span]),limits:l,using:&a)
            charts.append(try DefaultOriginalBSplineChartIssuer<NativeSnapshot,Field>().issue(source:child,chart:chart,field:f,limits:l,using:&a))
        }
        let parent=try DefaultOriginalSourceBindingIssuer(provider:RevolutionProvider<NativeSnapshot>()).bind(RevolutionInput(originalGenerator:child),limits:l,using:&a)
        let preparer=DefaultOriginalFiniteRevolutionLawPreparer<RevolutionInput<NativeSnapshot>,OriginalBSplineChartSelection,Field>()
        let all=try preparer.prepare(source:parent,generators:charts,field:f,axisLength:f.integer(2,using:&a),maximumCharts:2,limits:l,using:&a)
        try require(all.laws.count == 2)
        try all.admitProof(limits:l,using:&a)
        try require(f.compare(all.support[1].lower,f.integer(0,using:&a),using:&a) == .equal)
        try require(f.compare(all.support[1].upper,f.integer(1,using:&a),using:&a) == .equal)
        try require(all.laws[0].generator.chart.selection.spans == [1] && all.laws[1].generator.chart.selection.spans == [2])
        do { _ = try preparer.prepare(source:parent,generators:[charts[0]],field:f,axisLength:f.integer(2,using:&a),maximumCharts:2,limits:l,using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.invalidChart {}
        do { _ = try preparer.prepare(source:parent,generators:charts,field:f,axisLength:f.integer(2,using:&a),maximumCharts:1,limits:l,using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.chartLimit {}
    }
}
