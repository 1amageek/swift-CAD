import L0
import L1
import SourceIssuer

extension SourceFixtures {
    struct TraversalInput: OriginalTraversalSourceReading {
        let originalChild: OriginalSourceBinding<NativeSnapshot>
        let originalStart: Field.Value
        let originalEnd: Field.Value
    }
    struct TraversalProvider: OriginalSourceSnapshotting {
        func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing TraversalInput,
            limits: OriginalSourceIssuanceLimits, using admission: inout A
        ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<TraversalInput> {
            do { try admission.consumeWork(1) } catch { throw .scalar(error) }
            return .init(original:copy input,sourceDepth:input.originalChild.sourceDepth+1)
        }
    }
    typealias TraversalReceipt = OriginalRationalChartReceipt<TraversalInput,
        OriginalTraversalChartSelection<NativeSnapshot,OriginalBSplineChartSelection,Field>,Field>
    static func traversalReceipt<A: ExactScalarAdmission & ~Copyable>(start:Int = 4,end:Int = 3,
        using a:inout A) throws -> TraversalReceipt {
        let child = try issue(input(lower:2,upper:5),using:&a)
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:1),f = child.field
        let source = try DefaultOriginalSourceBindingIssuer(provider:TraversalProvider()).bind(
            TraversalInput(originalChild:child.source,originalStart:f.integer(start,using:&a),
                originalEnd:f.integer(end,using:&a)),limits:limits,using:&a)
        let chart = try source.chart(OriginalTraversalChartSelection(child:child),limits:limits,using:&a)
        return try DefaultOriginalTraversalChartIssuer<TraversalInput,OriginalBSplineChartSelection,Field>()
            .issue(source:source,chart:chart,field:f,limits:limits,using:&a)
    }
    public static func directedTraversalLaws() throws {
        var a = try TraceAdmission();let result = try traversalReceipt(using:&a)
        let f = result.field,r = result.polynomials,child = result.chart.selection.child
        for axis in 0..<4 {
            try require(try r.equals(result.homogeneous[axis],r.importing(child.homogeneous[axis],using:&a),using:&a))
        }
        try require(try r.equals(result.parameterTransport.numerators[0],
            r.subtracting(r.variable(0,using:&a),r.constant(f.integer(4,using:&a),using:&a),using:&a),using:&a))
        try require(try r.equals(result.parameterTransport.denominators[0],r.constant(f.integer(-1,using:&a),using:&a),using:&a))
        try require(try f.compare(result.support[0].lower,f.integer(3,using:&a),using:&a) == .equal)
        try require(try f.compare(result.support[0].upper,f.integer(4,using:&a),using:&a) == .equal)
        let endpoints = DefaultOriginalCurveEndpointIssuer<TraversalInput,
            OriginalTraversalChartSelection<NativeSnapshot,OriginalBSplineChartSelection,Field>,Field>()
        for (local,original) in [(4,0),(3,1)] {
            let endpoint = try endpoints.issue(source:result.source,curve:result,localParameter:f.integer(local,using:&a),
                originalParameter:f.integer(original,using:&a),limits:.init(remainingSourceDepth:1),using:&a)
            try require(try f.compare(endpoint.originalParameter,f.integer(original,using:&a),using:&a) == .equal)
        }
        do { _ = try traversalReceipt(start:3,end:3,using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.invalidSource {}
        do { _ = try traversalReceipt(start:-2,end:-1,using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.invalidChart {}
        let foreign = try issue(input(lower:2,upper:5),using:&a)
        let wrong = try result.source.chart(OriginalTraversalChartSelection(child:foreign),limits:.init(remainingSourceDepth:1),using:&a)
        let issuer = DefaultOriginalTraversalChartIssuer<TraversalInput,OriginalBSplineChartSelection,Field>()
        do { _ = try issuer.issue(source:result.source,chart:wrong,field:f,limits:.init(remainingSourceDepth:1),using:&a)
            throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.foreignBinding {}
        do { _ = try issuer.issue(source:result.source,chart:result.chart,field:f,limits:.init(remainingSourceDepth:0),using:&a)
            throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        var measured = try TraceAdmission();_ = try traversalReceipt(using:&measured)
        var exact = try TraceAdmission(work:measured.work,storage:measured.storageBytes);_ = try traversalReceipt(using:&exact)
        var work = try TraceAdmission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try traversalReceipt(using:&work);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.work))) {}
        var storage = try TraceAdmission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try traversalReceipt(using:&storage);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        var entry = try TraceAdmission();entry.base.cancel()
        do { _ = try traversalReceipt(using:&entry);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        var final = try TraceAdmission(cancelAtStorage:measured.storageCalls)
        do { _ = try traversalReceipt(using:&final);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        print("PASS exact directed traversal clipping, retained position/guard laws, signed original endpoints and atomic provenance/depth/budgets/cancel")
    }
}
