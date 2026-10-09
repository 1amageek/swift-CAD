import L0
import L1
import SourceIssuer

extension SourceFixtures {
    struct SurfaceCellInput:Sendable {
        let bounds:[[Field.Value]]
        let position:[ExactPolynomial<Field>]
    }
    struct RetainedSurfaceInput:OriginalRetainedSurfaceSourceReading {
        let originalField:Field
        let originalPolynomials:ExactPolynomialDomain<Field>
        let cells:[SurfaceCellInput]
        let originalProofDepth:ExactScalarDepth
        var originalCellCount:Int { cells.count }
        func originalCellLowerBound(at index:Int,axis:Int)->Field.Value { cells[index].bounds[axis][0] }
        func originalCellUpperBound(at index:Int,axis:Int)->Field.Value { cells[index].bounds[axis][1] }
        func originalCellHomogeneous(at index:Int)->[ExactPolynomial<Field>] { cells[index].position }
    }
    struct RetainedSurfaceProvider:OriginalSourceSnapshotting {
        func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing RetainedSurfaceInput,
            limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<RetainedSurfaceInput> {
            do { try a.consumeWork(1);return .init(original:copy input,sourceDepth:1) }
            catch { throw .scalar(error) }
        }
    }
    static func retainedSurface<A:ExactScalarAdmission & ~Copyable>(mode:Int=0,using a:inout A) throws -> OriginalFiniteRetainedSurfaceCharts<RetainedSurfaceInput> {
        let f=Field(),r=try ExactPolynomialDomain(field:f,variableCount:2,using:&a)
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a),two=try f.integer(2,using:&a)
        let third=try f.dividing(one,f.integer(3,using:&a),using:&a)
        let u=try r.variable(0,using:&a),v=try r.variable(1,using:&a)
        let pos=[try r.scaled(u,by:two,using:&a),try r.scaled(r.adding(v,r.multiplying(u,v,using:&a),using:&a),by:two,using:&a),try r.constant(zero,using:&a),try r.constant(two,using:&a)]
        let right=mode==2 ? try f.dividing(two,f.integer(3,using:&a),using:&a):third
        var cells=[SurfaceCellInput(bounds:[[zero,third],[zero,one]],position:pos)]
        if mode != 1 { cells.append(.init(bounds:[[right,one],[zero,one]],position:pos)) }
        let input=RetainedSurfaceInput(originalField:f,originalPolynomials:r,cells:cells,originalProofDepth:try .init(value:0,coefficient:0))
        let limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let binding=try DefaultOriginalSourceBindingIssuer(provider:RetainedSurfaceProvider()).bind(input,limits:limits,using:&a)
        return try DefaultOriginalFiniteRetainedSurfaceChartPreparer<RetainedSurfaceInput>().prepare(source:binding,maximumCharts:2,limits:limits,using:&a)
    }
    public static func retainedSurfaceLaws() throws {
        var a=try TraceAdmission();let family=try retainedSurface(using:&a),f=family.field
        let limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1),one=try f.integer(1,using:&a)
        let third=try f.dividing(one,f.integer(3,using:&a),using:&a),half=try f.dividing(one,f.integer(2,using:&a),using:&a)
        try require(family.laws.count==2 && family.support.count==2)
        for law in family.laws {
            let r=law.polynomials,point=[third,half]
            let d=try r.evaluated(law.denominator,at:point,using:&a).value
            let x=try f.dividing(r.evaluated(law.homogeneous[0],at:point,using:&a).value,d,using:&a)
            let y=try f.dividing(r.evaluated(law.homogeneous[1],at:point,using:&a).value,d,using:&a)
            try require(f.compare(x,third,using:&a) == .equal)
            try require(f.compare(y,f.multiplying(third,f.integer(2,using:&a),using:&a),using:&a) == .equal)
            try require(law.parameterTransport.numerators.count==2)
        }
        try family.admitProof(limits:limits,using:&a)
        for mode in [1,2] {
            do { _ = try retainedSurface(mode:mode,using:&a);throw Failure.incorrectEvidence }
            catch OriginalSourceIssuanceFailure.invalidChart {}
        }
        do { _ = try DefaultOriginalFiniteRetainedSurfaceChartPreparer<RetainedSurfaceInput>().prepare(source:family.source,maximumCharts:1,limits:limits,using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.chartLimit {}
        var measured=try TraceAdmission();_ = try retainedSurface(using:&measured)
        var exact=try TraceAdmission(work:measured.work,storage:measured.storageBytes);_ = try retainedSurface(using:&exact)
        var work=try TraceAdmission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try retainedSurface(using:&work);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.work))) {}
        var storage=try TraceAdmission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try retainedSurface(using:&storage);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.storage))) {}
        var cancel=try TraceAdmission(cancelAtStorage:measured.storageCalls)
        do { _ = try retainedSurface(using:&cancel);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        print("PASS M4 retained surface position laws, exact whole-square coverage, closed sides and atomic failures")
    }
}
