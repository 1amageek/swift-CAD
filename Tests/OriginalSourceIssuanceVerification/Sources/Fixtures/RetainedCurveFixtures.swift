import L0
import L1
import SourceIssuer

extension SourceFixtures {
    struct RetainedCurveInput:OriginalRetainedCurveSourceReading {
        let originalField:Field
        let originalPolynomials:ExactPolynomialDomain<Field>
        let originalProofDepth:ExactScalarDepth
        let bounds:[[Field.Value]]
        let position:[ExactPolynomial<Field>]
        var originalCellCount:Int { bounds.count }
        func originalCellLowerBound(at index:Int)->Field.Value { bounds[index][0] }
        func originalCellUpperBound(at index:Int)->Field.Value { bounds[index][1] }
        func originalCellHomogeneous(at index:Int)->[ExactPolynomial<Field>] { position }
    }
    struct RetainedCurveProvider:OriginalSourceSnapshotting {
        func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing RetainedCurveInput,
            limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<RetainedCurveInput> {
            do { try a.consumeWork(1);return .init(original:copy input,sourceDepth:1) }
            catch { throw .scalar(error) }
        }
    }
    static func retainedCurve<A:ExactScalarAdmission & ~Copyable>(mode:Int=0,using a:inout A) throws -> OriginalFiniteRetainedCurveCharts<RetainedCurveInput> {
        let f=Field(),r=try ExactPolynomialDomain(field:f,variableCount:1,using:&a)
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a),two=try f.integer(2,using:&a)
        let third=try f.dividing(one,f.integer(3,using:&a),using:&a)
        let t=try r.variable(0,using:&a)
        let z=try r.polynomial(terms:[.init(powers:[3],coefficient:f.integer(10,using:&a)),.init(powers:[4],coefficient:f.integer(-15,using:&a)),.init(powers:[5],coefficient:f.integer(6,using:&a))],using:&a)
        var bounds=[[zero,third]]
        if mode != 1 { bounds.append([mode==2 ? try f.multiplying(two,third,using:&a):third,one]) }
        let input=RetainedCurveInput(originalField:f,originalPolynomials:r,originalProofDepth:try .init(value:1,coefficient:2),bounds:bounds,
            position:[t,try r.constant(zero,using:&a),z,try r.constant(one,using:&a)])
        let limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let binding=try DefaultOriginalSourceBindingIssuer(provider:RetainedCurveProvider()).bind(input,limits:limits,using:&a)
        return try DefaultOriginalFiniteRetainedCurveChartPreparer<RetainedCurveInput>().prepare(source:binding,maximumCharts:2,limits:limits,using:&a)
    }
    public static func retainedCurveLaws() throws {
        var a=try TraceAdmission();let family=try retainedCurve(using:&a),f=family.field
        let limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let quarter=try f.dividing(f.integer(1,using:&a),f.integer(4,using:&a),using:&a)
        let expected=try f.binary64(exactly:0.103515625,using:&a)
        try require(family.laws.count==2 && family.proofDepth.value>=1 && family.proofDepth.coefficient>=2)
        let half=try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a)
        for (index,local,target) in [(0,quarter,expected),(1,half,half)] {
            let law=family.laws[index],r=law.polynomials
            let z=try f.dividing(r.evaluated(law.homogeneous[2],at:[local],using:&a).value,r.evaluated(law.denominator,at:[local],using:&a).value,using:&a)
            try require(f.compare(z,target,using:&a) == .equal)
        }
        let third=try f.dividing(f.integer(1,using:&a),f.integer(3,using:&a),using:&a)
        let join=try f.dividing(f.integer(17,using:&a),f.integer(81,using:&a),using:&a)
        for law in family.laws {
            let r=law.polynomials
            let z=try f.dividing(r.evaluated(law.homogeneous[2],at:[third],using:&a).value,r.evaluated(law.denominator,at:[third],using:&a).value,using:&a)
            try require(f.compare(z,join,using:&a) == .equal)
        }
        try family.admitProof(limits:limits,using:&a)
        for mode in [1,2] {
            do { _ = try retainedCurve(mode:mode,using:&a);throw Failure.incorrectEvidence }
            catch OriginalSourceIssuanceFailure.invalidChart {}
        }
        do { _ = try DefaultOriginalFiniteRetainedCurveChartPreparer<RetainedCurveInput>().prepare(source:family.source,maximumCharts:1,limits:limits,using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.chartLimit {}
        var shallow=ExactScalarLedger(limits:try .init(work:1000,storageBytes:1000,valueDepth:0,coefficientDepth:0))
        do { try family.admitProof(limits:limits,using:&shallow);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.valueDepth)) {}
        var measured=try TraceAdmission();_ = try retainedCurve(using:&measured)
        var exact=try TraceAdmission(work:measured.work,storage:measured.storageBytes);_ = try retainedCurve(using:&exact)
        var work=try TraceAdmission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try retainedCurve(using:&work);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.work))) {}
        var storage=try TraceAdmission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try retainedCurve(using:&storage);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.storage))) {}
        var cancel=try TraceAdmission(cancelAtStorage:measured.storageCalls)
        do { _ = try retainedCurve(using:&cancel);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        print("PASS M4 retained original curve law, complete exact cells, inherited decision depth and atomic failures")
    }
}
