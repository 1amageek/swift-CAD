import L0
import L1
import SourceIssuer

struct LiftAdmission: ~Copyable, ExactScalarAdmission {
    var ledger: ExactScalarLedger
    var storageCalls=0
    let cancelAt: Int?
    init(work: Int=100_000_000,storage: Int=400_000_000,depth: Int=32,cancelAt: Int?=nil) throws {
        ledger = .init(limits:try .init(work:work,storageBytes:storage,valueDepth:depth,coefficientDepth:depth))
        self.cancelAt=cancelAt
    }
    mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
    mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) { try ledger.consumeWork(units) }
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
        try ledger.retainStorage(bytes:bytes);storageCalls += 1
        if storageCalls==cancelAt { ledger.cancel() }
    }
    mutating func visitCell(axis: ExactScalarRootAxis,depth: Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
    mutating func admitDepth(value: Int,coefficient: Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
}

enum LiftChecks {
    struct Failure: Error { let line: Int }
    nonisolated static func require(_ value: Bool,line: Int = #line) throws {
        guard value else { print("FAIL periodic lift");throw Failure(line:line) }
    }
    nonisolated static func scalarFailure(_ body: () throws -> Void) throws {
        do { try body();throw Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.cancelled)) {}
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(_)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(_))) {}
    }
    nonisolated static func graph<P: OriginalPeriodicNativeSurfaceLiftGraphQuerying>(family: P,template: Int,
        cycles: [ExactRationalCoefficient],using a: inout LiftAdmission) throws
        -> OriginalParametricGraphReceipt<P.Source,OriginalExactScalarDomain,OriginalSurfaceLiftGraphEvidence<P.Source>> {
        try family.graph(template:template,cycles:cycles,maximumCharts:32,
            limits:.init(remainingSourceDepth:8),using:&a)
    }
    nonisolated static func run<S: OriginalSurfaceLiftSourceReading>(_ family: OriginalPeriodicNativeSurfaceLiftGraphs<S>,
        twoAxes: Bool,nonmonotone: Bool=false,constant: Bool=false) throws {
        var a=try LiftAdmission();let f=family.field,q=ExactRationalScalarDomain(),l=try OriginalSourceIssuanceLimits(remainingSourceDepth:8)
        try require(family.templateCount==(twoAxes ? 9:3) && family.integerFamilyRank==(twoAxes ? 2:1))
        let zero=try q.integer(0,using:&a)
        var observed=0
        for t in [0.0,0.25,0.5,0.75,1.0] {
            let uv=constant ? 3.0 : nonmonotone ? -3+18*t*(1-t) : -3+9*t
            let values=[try f.binary64(exactly:t,using:&a),try f.binary64(exactly:uv,using:&a),
                        try f.binary64(exactly:twoAxes ? uv:0.5,using:&a)]
            var count=0
            for u in -2...2 { for v in (twoAxes ? -2:0)...(twoAxes ? 2:0) {
                let cycles=[try q.integer(u,using:&a),try q.integer(v,using:&a)]
                for template in 0..<family.templateCount {
                    let g=try graph(family:family,template:template,cycles:cycles,using:&a)
                    try require(g.layout.parameters == [0] && g.layout.auxiliaries == [1,2])
                    if try g.admits(values,limits:l,using:&a) {
                        count += 1
                        var x=uv.truncatingRemainder(dividingBy:3);if x<0 { x += 3 }
                        let expected:[Double]=x<=1 ? [x,0,0] : x<=2 ? [2-x,x-1,0]:[0,3-x,0]
                        let result=try position(g,values:values,using:&a)
                        for axis in 0..<3 {
                            let target=axis==1 && twoAxes ? expected[1]+expected[0] : axis==2 ? (twoAxes ? expected[1]:0.5):expected[axis]
                            try require(f.compare(result[axis],f.binary64(exactly:target,using:&a),using:&a) == .equal)
                        }
                    }
                }
            } }
            let onBoundary=uv.rounded(.towardZero)==uv
            try require(count==(onBoundary ? (twoAxes ? 4:2):1));observed += count
            // Same XYZ after a period is not the authored pcurve's UV witness.
            var wrong=values;wrong[1]=try f.adding(values[1],f.integer(3,using:&a),using:&a)
            let g=try graph(family:family,template:0,cycles:[zero,zero],using:&a)
            try require(!g.admits(wrong,limits:l,using:&a))
        }
        let cycles=[zero,zero]
        var measured=try LiftAdmission();_=try graph(family:family,template:0,cycles:cycles,using:&measured)
        var exact=try LiftAdmission(work:measured.ledger.work,storage:measured.ledger.storageBytes)
        _=try graph(family:family,template:0,cycles:cycles,using:&exact)
        var work=try LiftAdmission(work:measured.ledger.work-1)
        try scalarFailure { _=try graph(family:family,template:0,cycles:cycles,using:&work) }
        var storage=try LiftAdmission(storage:measured.ledger.storageBytes-1)
        try scalarFailure { _=try graph(family:family,template:0,cycles:cycles,using:&storage) }
        var entry=try LiftAdmission();entry.ledger.cancel()
        try scalarFailure { _=try graph(family:family,template:0,cycles:cycles,using:&entry) }
        for call in [1,measured.storageCalls] {
            var cancelled=try LiftAdmission(cancelAt:call)
            try scalarFailure { _=try graph(family:family,template:0,cycles:cycles,using:&cancelled) }
        }
        do { _=try family.graph(template:family.templateCount,cycles:cycles,maximumCharts:32,limits:l,using:&a);throw Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.invalidChart {}
        do { _=try family.graph(template:0,cycles:[zero],maximumCharts:32,limits:l,using:&a);throw Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.invalidChart {}
        let half=try q.dividing(q.integer(1,using:&a),q.integer(2,using:&a),using:&a)
        do { _=try family.graph(template:0,cycles:[half,zero],maximumCharts:32,limits:l,using:&a);throw Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.invalidChart {}
        if !twoAxes {
            do { _=try family.graph(template:0,cycles:[zero,q.integer(1,using:&a)],maximumCharts:32,limits:l,using:&a);throw Failure(line:#line) }
            catch OriginalSourceIssuanceFailure.invalidChart {}
        }
        do { _=try family.graph(template:0,cycles:cycles,maximumCharts:family.templateCount-1,limits:l,using:&a);throw Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.chartLimit {}
        do { _=try family.graph(template:0,cycles:cycles,maximumCharts:32,limits:.init(remainingSourceDepth:0),using:&a);throw Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        print("PASS periodic lift all translated chart sides, authored UV, roots/guards, generic requirement, exact resources/cancel/depth")
    }
    nonisolated static func position<S: OriginalSurfaceLiftSourceReading>(
        _ g: OriginalParametricGraphReceipt<S,OriginalExactScalarDomain,OriginalSurfaceLiftGraphEvidence<S>>,
        values: [OriginalExactScalar],using a: inout LiftAdmission) throws -> [OriginalExactScalar] {
        let f=g.field,r=g.polynomials,d=try r.evaluated(g.homogeneous[3],at:values,using:&a).value
        var result:[OriginalExactScalar]=[]
        for axis in 0..<3 { result.append(try f.dividing(r.evaluated(g.homogeneous[axis],at:values,using:&a).value,d,using:&a)) }
        return result
    }
    nonisolated static func preparation<S: OriginalSurfaceLiftSourceReading>(
        _ family: OriginalPeriodicNativeSurfaceLiftGraphs<S>,foreign: OriginalPeriodicNativeSurfaceLiftGraphs<S>) throws {
        let issuer=DefaultOriginalPeriodicNativeSurfaceLiftGraphPreparer<S>(),l=try OriginalSourceIssuanceLimits(remainingSourceDepth:8)
        func prepare(_ a: inout LiftAdmission) throws {
            _=try issuer.prepare(source:family.source,surface:family.surface,pcurve:family.pcurve,maximumCharts:32,limits:l,using:&a)
        }
        var measured=try LiftAdmission();try prepare(&measured)
        var exact=try LiftAdmission(work:measured.ledger.work,storage:measured.ledger.storageBytes);try prepare(&exact)
        var work=try LiftAdmission(work:measured.ledger.work-1)
        try scalarFailure { try prepare(&work) }
        var storage=try LiftAdmission(storage:measured.ledger.storageBytes-1)
        try scalarFailure { try prepare(&storage) }
        for call in [1,measured.storageCalls] {
            var cancelled=try LiftAdmission(cancelAt:call)
            try scalarFailure { try prepare(&cancelled) }
        }
        var a=try LiftAdmission()
        do { _=try issuer.prepare(source:family.source,surface:foreign.surface,pcurve:family.pcurve,maximumCharts:32,limits:l,using:&a);throw Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.foreignBinding {}
        do { _=try issuer.prepare(source:family.source,surface:family.surface,pcurve:foreign.pcurve,maximumCharts:32,limits:l,using:&a);throw Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.foreignBinding {}
        do { _=try issuer.prepare(source:family.source,surface:family.surface,pcurve:family.pcurve,maximumCharts:family.templateCount-1,limits:l,using:&a);throw Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.chartLimit {}
        // A full-period shift has the same surface XYZ and lies inside the
        // shifted chart, but it is still the wrong authored pcurve UV.
        let q=ExactRationalScalarDomain(),cycles=[try q.integer(1,using:&a),try q.integer(0,using:&a)]
        let g=try graph(family:family,template:0,cycles:cycles,using:&a),f=family.field
        let wrong=[try f.dividing(f.integer(1,using:&a),f.integer(3,using:&a),using:&a),try f.integer(3,using:&a),try f.binary64(exactly:0.5,using:&a)]
        try require(!g.admits(wrong,limits:l,using:&a))
        print("PASS periodic lift preparation exact resources/cancel/foreign children and sameXYZ wrong authored UV")
    }
    nonisolated static func huge<S: OriginalSurfaceLiftSourceReading>(_ family: OriginalPeriodicNativeSurfaceLiftGraphs<S>) throws {
        var a=try LiftAdmission();let f=family.field,q=ExactRationalScalarDomain()
        let cycle=try q.canonical(sign:1,numerator:[0,0,0,1],denominator:[1],using:&a),zero=try q.integer(0,using:&a)
        let graph=try graph(family:family,template:0,cycles:[cycle,zero],using:&a)
        let values=[try f.integer(0,using:&a),try f.multiplying(f.rational(exactly:cycle,using:&a),f.integer(3,using:&a),using:&a),try f.binary64(exactly:0.5,using:&a)]
        try require(graph.admits(values,limits:.init(remainingSourceDepth:8),using:&a))
        let xyz=try position(graph,values:values,using:&a)
        try require(f.sign(of:xyz[0],using:&a) == .zero && f.sign(of:xyz[1],using:&a) == .zero)
        print("PASS periodic lift cycle exceeds machine Int without truncation")
    }
}
