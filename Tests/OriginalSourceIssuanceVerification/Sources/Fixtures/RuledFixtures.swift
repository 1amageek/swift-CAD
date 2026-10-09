import L0
import L1
import SourceIssuer

extension SourceFixtures {
    struct LineInput: OriginalLinearSourceReading {
        let origin: [Double]
        let direction: [Double]
        func originCoordinate(in axis: Int) -> Double { origin[axis] }
        func directionCoordinate(in axis: Int) -> Double { direction[axis] }
    }
    struct LineProvider: OriginalSourceSnapshotting {
        func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing LineInput,
            limits: OriginalSourceIssuanceLimits, using admission: inout A
        ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<LineInput> {
            do { try admission.consumeWork(1) } catch { throw .scalar(error) }
            guard input.origin.count == 3, input.direction.count == 3 else { throw .invalidSource }
            return .init(original: copy input, sourceDepth: 0)
        }
    }
    struct RuledInput: OriginalRuledSourceReading {
        let firstBoundary: OriginalSourceBinding<NativeSnapshot>
        let secondBoundary: OriginalSourceBinding<LineInput>
        let originalLowerU: Double
        let originalUpperU: Double
    }
    struct RuledProvider: OriginalSourceSnapshotting {
        func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing RuledInput,
            limits: OriginalSourceIssuanceLimits, using admission: inout A
        ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<RuledInput> {
            do { try admission.consumeWork(1) } catch { throw .scalar(error) }
            return .init(original: copy input, sourceDepth:1)
        }
    }
    typealias RuledSourceReceipt = OriginalRationalChartReceipt<RuledInput,
        OriginalRuledChartSelection<NativeSnapshot,OriginalBSplineChartSelection,LineInput,OriginalLinearChartSelection,Field>,Field>
    static func ruledReceipt<A: ExactScalarAdmission & ~Copyable>(using admission: inout A) throws -> RuledSourceReceipt {
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let native = try issue(input(),using:&admission)
        let line = try DefaultOriginalSourceBindingIssuer(provider:LineProvider())
            .bind(LineInput(origin:[0,1,1],direction:[2,0,0]),limits:limits,using:&admission)
        let lineChart = try line.chart(OriginalLinearChartSelection(lower:0.25,upper:0.75),limits:limits,using:&admission)
        let end = try DefaultOriginalLinearChartIssuer<LineInput,Field>()
            .issue(source:line,chart:lineChart,field:.init(),limits:limits,using:&admission)
        let parent = try DefaultOriginalSourceBindingIssuer(provider:RuledProvider())
            .bind(RuledInput(firstBoundary:native.source,secondBoundary:line,originalLowerU:0,originalUpperU:1),
                limits:limits,using:&admission)
        let chart = try parent.chart(OriginalRuledChartSelection(first:native,second:end),limits:limits,using:&admission)
        return try DefaultOriginalRuledChartIssuer<RuledInput,OriginalBSplineChartSelection,OriginalLinearChartSelection,Field>()
            .issue(source:parent,chart:chart,field:.init(),limits:limits,using:&admission)
    }
    public static func ruledLaws() throws {
        try finiteFamilyCharts()
        var a = try TraceAdmission()
        let receipt = try ruledReceipt(using:&a), r = receipt.polynomials, f = receipt.field
        let u = try r.variable(0,using:&a), v = try r.variable(1,using:&a)
        let one = try r.constant(f.integer(1,using:&a),using:&a)
        let uv = try r.multiplying(u,v,using:&a)
        let u2 = try r.multiplying(u,u,using:&a)
        let expectedX = try r.scaled(r.adding(u,r.multiplying(u2,v,using:&a),using:&a),by:f.integer(2,using:&a),using:&a)
        let expectedY = try r.adding(v,uv,using:&a)
        let expectedW = try r.adding(one,u,using:&a)
        for (axis, law) in [(0,expectedX),(1,expectedY),(2,expectedY),(3,expectedW)] {
            try require(try r.equals(receipt.homogeneous[axis],law,using:&a))
        }
        try require(try f.compare(receipt.support[0].lower,f.binary64(exactly:0.25,using:&a),using:&a) == .equal)
        try require(try f.compare(receipt.support[0].upper,f.binary64(exactly:0.75,using:&a),using:&a) == .equal)
        try require(receipt.source.sourceDepth == 1 && receipt.chart.selection.first.source.original.input.weights == [1,2])
        let foreign = try issue(input(),using:&a)
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let wrong = try receipt.source.chart(OriginalRuledChartSelection(first:foreign,second:receipt.chart.selection.second),
            limits:limits,using:&a)
        do { _ = try DefaultOriginalRuledChartIssuer<RuledInput,OriginalBSplineChartSelection,OriginalLinearChartSelection,Field>()
            .issue(source:receipt.source,chart:wrong,field:.init(),limits:limits,using:&a)
            throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.foreignBinding {}
        var measured = try TraceAdmission(); _ = try ruledReceipt(using:&measured)
        var exact = try TraceAdmission(work:measured.work,storage:measured.storageBytes)
        _ = try ruledReceipt(using:&exact)
        var lowWork = try TraceAdmission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try ruledReceipt(using:&lowWork); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        var lowStorage = try TraceAdmission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try ruledReceipt(using:&lowStorage); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        var finalCancelled = try TraceAdmission(cancelAtStorage:measured.storageCalls)
        do { _ = try ruledReceipt(using:&finalCancelled); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        var entryCancelled = try TraceAdmission(); entryCancelled.base.cancel()
        do { _ = try ruledReceipt(using:&entryCancelled); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        for axis in [ExactScalarRootAxis.value, .coefficient] {
            var rejected = try TraceAdmission(rejectDepth:axis)
            do { _ = try ruledReceipt(using:&rejected); throw Failure.incorrectEvidence }
            catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(let resource))) {
                try require(resource == (axis == .value ? .valueDepth : .coefficientDepth))
            }
        }
        let issuer = DefaultOriginalRuledChartIssuer<RuledInput,OriginalBSplineChartSelection,OriginalLinearChartSelection,Field>()
        do { _ = try issuer.issue(source:receipt.source,chart:receipt.chart,field:.init(),
            limits:.init(remainingSourceDepth:0),using:&a); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        for (lower,upper) in [(1.0,1.0),(2.0,3.0)] {
            let selected = try receipt.source.original.secondBoundary.chart(
                OriginalLinearChartSelection(lower:lower,upper:upper),limits:limits,using:&a)
            let end = try DefaultOriginalLinearChartIssuer<LineInput,Field>().issue(
                source:receipt.source.original.secondBoundary,chart:selected,field:.init(),limits:limits,using:&a)
            let chart = try receipt.source.chart(OriginalRuledChartSelection(first:receipt.chart.selection.first,second:end),
                limits:limits,using:&a)
            if lower == 1 {
                let point = try issuer.issue(source:receipt.source,chart:chart,field:.init(),limits:limits,using:&a)
                try require(try point.field.compare(point.support[0].lower,point.support[0].upper,using:&a) == .equal)
            } else {
                do { _ = try issuer.issue(source:receipt.source,chart:chart,field:.init(),limits:limits,using:&a)
                    throw Failure.incorrectEvidence }
                catch OriginalSourceIssuanceFailure.invalidChart {}
            }
        }
        print("PASS heterogeneous Native/line ruled whole laws, product W, exact support, retained child owners and atomic budgets/cancel/depth")
    }
}
