import L0
import L1
import SourceIssuer

extension SourceFixtures {
    struct GuideInput:OriginalGuideSourceReading {
        let children:[OriginalSourceBinding<NativeSnapshot>]
        let stations:[Field.Value]
        let ordinals:[Int]
        var originalTraversalCount:Int { children.count }
        func originalTraversal(at index:Int)->OriginalSourceBinding<NativeSnapshot> { children[index] }
        func originalStation(at index:Int)->Field.Value { stations[index] }
        func originalSegmentOrdinal(at index:Int)->Int { ordinals[index] }
    }
    struct GuideProvider:OriginalSourceSnapshotting {
        func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing GuideInput,
            limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<GuideInput> {
            do {
                try a.consumeWork(1)
                guard input.children.count==2,input.stations.count==3,input.ordinals.count==2,
                    input.children[0].original.input.controls.last == input.children[1].original.input.controls.first else {
                    throw OriginalSourceIssuanceFailure.invalidSource
                }
                return .init(original:copy input,sourceDepth:1)
            } catch let failure as OriginalSourceIssuanceFailure { throw failure }
            catch let failure as ExactScalarFailure { throw .scalar(failure) }
            catch { throw .sourceRejected(error) }
        }
    }
    typealias GuideFamily=OriginalFiniteGuideChartFamily<GuideInput,OriginalBSplineChartSelection,Field>
    static func guide<A:ExactScalarAdmission & ~Copyable>(using a:inout A) throws -> GuideFamily {
        let f=Field(),limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        var bindings:[OriginalSourceBinding<NativeSnapshot>]=[],charts:[[Receipt]]=[]
        for points in [[[0.0,0,0],[1,0,0]],[[1.0,0,0],[3,0,0]]] {
            let input=NativeInput(degrees:[1],knots:[[0,0,1,1]],counts:[2],controls:points,weights:[1,1],periodic:[false])
            let b=try DefaultOriginalSourceBindingIssuer(provider:NativeProvider()).bind(input,limits:limits,using:&a)
            let c=try b.chart(OriginalBSplineChartSelection(spans:[1]),limits:limits,using:&a)
            bindings.append(b);charts.append([try DefaultOriginalBSplineChartIssuer<NativeSnapshot,Field>().issue(source:b,chart:c,field:f,limits:limits,using:&a)])
        }
        let third=try f.dividing(f.integer(1,using:&a),f.integer(3,using:&a),using:&a)
        let source=try DefaultOriginalSourceBindingIssuer(provider:GuideProvider()).bind(
            GuideInput(children:bindings,stations:[try f.integer(0,using:&a),third,try f.integer(1,using:&a)],ordinals:[3,7]),limits:limits,using:&a)
        return try DefaultOriginalFiniteGuideChartPreparer<GuideInput,OriginalBSplineChartSelection,Field>().prepare(
            source:source,traversals:charts,field:f,maximumCharts:2,limits:limits,using:&a)
    }
    public static func guideLaws() throws {
        var a=try TraceAdmission();let family=try guide(using:&a),f=family.field
        let limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1),one=try f.integer(1,using:&a)
        let half=try f.dividing(one,f.integer(2,using:&a),using:&a),third=try f.dividing(one,f.integer(3,using:&a),using:&a)
        let sixth=try f.dividing(one,f.integer(6,using:&a),using:&a),twoThirds=try f.multiplying(third,f.integer(2,using:&a),using:&a)
        try require(family.laws.count==2 && family.laws[0].originalSegmentOrdinal==3 && family.laws[1].originalSegmentOrdinal==7)
        for (index,expected) in [(0,sixth),(1,twoThirds)] {
            let law=family.laws[index]
            let t=try f.dividing(law.polynomials.evaluated(law.parameterTransport.numerators[0],at:[half],using:&a).value,
                law.polynomials.evaluated(law.parameterTransport.denominators[0],at:[half],using:&a).value,using:&a)
            try require(f.compare(t,expected,using:&a) == .equal)
        }
        for (index,local) in [(0,one),(1,try f.integer(0,using:&a))] {
            let law=family.laws[index]
            let t=try f.dividing(law.polynomials.evaluated(law.parameterTransport.numerators[0],at:[local],using:&a).value,
                law.polynomials.evaluated(law.parameterTransport.denominators[0],at:[local],using:&a).value,using:&a)
            let x=try f.dividing(law.polynomials.evaluated(law.homogeneous[0],at:[local],using:&a).value,
                law.polynomials.evaluated(law.homogeneous[3],at:[local],using:&a).value,using:&a)
            try require(f.compare(t,third,using:&a) == .equal && f.compare(x,one,using:&a) == .equal)
        }
        try family.admitProof(limits:limits,using:&a)
        let preparer=DefaultOriginalFiniteGuideChartPreparer<GuideInput,OriginalBSplineChartSelection,Field>()
        do { _ = try preparer.prepare(source:family.source,traversals:[[family.laws[0].child],[]],field:f,maximumCharts:2,limits:limits,using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.invalidChart {}
        do { _ = try preparer.prepare(source:family.source,traversals:[[family.laws[0].child],[family.laws[1].child]],field:f,maximumCharts:1,limits:limits,using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.chartLimit {}
        let foreign=try guide(using:&a)
        do { _ = try preparer.prepare(source:family.source,traversals:[[foreign.laws[0].child],[family.laws[1].child]],field:f,maximumCharts:2,limits:limits,using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.foreignBinding {}
        var measured=try TraceAdmission();_ = try guide(using:&measured)
        var exact=try TraceAdmission(work:measured.work,storage:measured.storageBytes);_ = try guide(using:&exact)
        var lowWork=try TraceAdmission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try guide(using:&lowWork);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.work))) {}
        var lowStorage=try TraceAdmission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try guide(using:&lowStorage);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.storage))) {}
        var final=try TraceAdmission(cancelAtStorage:measured.storageCalls)
        do { _ = try guide(using:&final);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        print("PASS M4 retained guide original laws, exact non-dyadic stations, both join incidents, full coverage and atomic failures")
    }
}
