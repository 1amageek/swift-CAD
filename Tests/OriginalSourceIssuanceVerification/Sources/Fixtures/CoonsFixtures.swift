import L0
import L1
import SourceIssuer

extension SourceFixtures {
    struct CoonsInput: OriginalCoonsSourceReading {
        let bottomBoundary: OriginalSourceBinding<NativeSnapshot>
        let topBoundary: OriginalSourceBinding<ParameterInput<LineInput>>
        let leftBoundary: OriginalSourceBinding<LineInput>
        let rightBoundary: OriginalSourceBinding<LineInput>
    }
    struct CoonsProvider: OriginalSourceSnapshotting {
        func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing CoonsInput,
            limits: OriginalSourceIssuanceLimits, using admission: inout A
        ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<CoonsInput> {
            do { try admission.consumeWork(1) } catch { throw .scalar(error) }
            return .init(original: copy input, sourceDepth: 2)
        }
    }
    typealias CoonsSelection = OriginalCoonsChartSelection<NativeSnapshot, OriginalBSplineChartSelection,
        ParameterInput<LineInput>, OriginalParameterImageChartSelection<LineInput, OriginalLinearChartSelection, Field>,
        LineInput, OriginalLinearChartSelection, LineInput, OriginalLinearChartSelection, Field>
    typealias CoonsReceipt = OriginalRationalChartReceipt<CoonsInput, CoonsSelection, Field>
    typealias CoonsIssuer = DefaultOriginalCoonsChartIssuer<CoonsInput, OriginalBSplineChartSelection,
        OriginalParameterImageChartSelection<LineInput, OriginalLinearChartSelection, Field>,
        OriginalLinearChartSelection, OriginalLinearChartSelection, Field>
    static func coonsBoundary<S: Sendable,C: Sendable,A: ExactScalarAdmission & ~Copyable>(
        _ curve: OriginalRationalChartReceipt<S,C,Field>, start: Int = 0, end: Int = 1,
        using a: inout A
    ) throws -> OriginalCoonsBoundarySelection<S,C,Field> {
        let issuer = DefaultOriginalCurveEndpointIssuer<S,C,Field>(),f = curve.field
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth: 2)
        let first = try issuer.issue(source: curve.source, curve: curve,
            localParameter: f.integer(start,using:&a),originalParameter:f.integer(0,using:&a),limits:limits,using:&a)
        let last = try issuer.issue(source: curve.source, curve: curve,
            localParameter: f.integer(end,using:&a),originalParameter:f.integer(1,using:&a),limits:limits,using:&a)
        return .init(curve:curve,start:first,end:last)
    }
    static func coonsLine<A: ExactScalarAdmission & ~Copyable>(_ origin:[Double],_ direction:[Double],
        using a:inout A
    ) throws -> OriginalRationalChartReceipt<LineInput,OriginalLinearChartSelection,Field> {
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:2)
        let source = try DefaultOriginalSourceBindingIssuer(provider:LineProvider()).bind(
            LineInput(origin:origin,direction:direction),limits:limits,using:&a)
        let chart = try source.chart(OriginalLinearChartSelection(lower:0,upper:1),limits:limits,using:&a)
        return try DefaultOriginalLinearChartIssuer<LineInput,Field>().issue(source:source,chart:chart,
            field:.init(),limits:limits,using:&a)
    }
    static func coonsReceipt<A: ExactScalarAdmission & ~Copyable>(badCorner:Bool = false,
        using a:inout A) throws -> CoonsReceipt {
        let bottom = try issue(input(),using:&a)
        let topLine = try coonsLine([1,1,0],[-1,0,0],using:&a)
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:2)
        let topSource = try DefaultOriginalSourceBindingIssuer(provider:ParameterProvider<LineInput>()).bind(
            ParameterInput(originalChild:topLine.source,gains:[(-1,1)],offsets:[1],axes:[0],hasSpatialAction:false),
            limits:limits,using:&a)
        let topChart = try topSource.chart(OriginalParameterImageChartSelection(child:topLine),limits:limits,using:&a)
        let top = try DefaultOriginalParameterImageChartIssuer<ParameterInput<LineInput>,OriginalLinearChartSelection,Field>()
            .issue(source:topSource,chart:topChart,field:topLine.field,limits:limits,using:&a)
        let left = try coonsLine([0,0,0],[0,1,0],using:&a)
        let right = try coonsLine([1,0,badCorner ? Double.leastNonzeroMagnitude : 0],[0,1,0],using:&a)
        let parent = try DefaultOriginalSourceBindingIssuer(provider:CoonsProvider()).bind(
            CoonsInput(bottomBoundary:bottom.source,topBoundary:top.source,leftBoundary:left.source,rightBoundary:right.source),
            limits:limits,using:&a)
        let selection = CoonsSelection(bottom:try coonsBoundary(bottom,using:&a),
            top:try coonsBoundary(top,start:1,end:0,using:&a),left:try coonsBoundary(left,using:&a),
            right:try coonsBoundary(right,using:&a))
        let chart = try parent.chart(selection,limits:limits,using:&a)
        return try CoonsIssuer().issue(source:parent,chart:chart,field:bottom.field,limits:limits,using:&a)
    }
    public static func coonsLaws() throws {
        var a = try TraceAdmission()
        let receipt = try coonsReceipt(using:&a),r = receipt.polynomials,f = receipt.field
        let u = try r.variable(0,using:&a),v = try r.variable(1,using:&a)
        let unit = try r.constant(f.integer(1,using:&a),using:&a)
        let uv = try r.multiplying(u,v,using:&a),u2v = try r.multiplying(u,uv,using:&a)
        let x = try r.negated(r.adding(r.subtracting(r.scaled(u,by:f.integer(2,using:&a),using:&a),uv,using:&a),u2v,using:&a),using:&a)
        let y = try r.negated(r.adding(v,uv,using:&a),using:&a)
        let w = try r.negated(r.adding(unit,u,using:&a),using:&a)
        try require(try r.equals(receipt.homogeneous[0],x,using:&a))
        try require(try r.equals(receipt.homogeneous[1],y,using:&a))
        try require(try r.isZero(receipt.homogeneous[2],using:&a))
        try require(try r.equals(receipt.homogeneous[3],w,using:&a))
        for axis in 0..<2 {
            try require(try f.compare(receipt.support[axis].lower,f.integer(0,using:&a),using:&a) == .equal)
            try require(try f.compare(receipt.support[axis].upper,f.integer(1,using:&a),using:&a) == .equal)
        }
        try require(receipt.proofDepth != nil && receipt.chart.selection.top.start.curve.source.sourceDepth == 1)
        do { _ = try coonsReceipt(badCorner:true,using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.invalidSource {}
        let foreign = try issue(input(),using:&a),s = receipt.chart.selection
        let wrong = try receipt.source.chart(CoonsSelection(bottom:try coonsBoundary(foreign,using:&a),
            top:s.top,left:s.left,right:s.right),limits:.init(remainingSourceDepth:2),using:&a)
        do { _ = try CoonsIssuer().issue(source:receipt.source,chart:wrong,field:f,
            limits:.init(remainingSourceDepth:2),using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.foreignBinding {}
        let endpointIssuer = DefaultOriginalCurveEndpointIssuer<NativeSnapshot,OriginalBSplineChartSelection,Field>()
        for (local,original) in [(2,1),(0,1)] {
            do { _ = try endpointIssuer.issue(source:s.bottom.curve.source,curve:s.bottom.curve,
                localParameter:f.integer(local,using:&a),originalParameter:f.integer(original,using:&a),
                limits:.init(remainingSourceDepth:2),using:&a);throw Failure.incorrectEvidence }
            catch OriginalSourceIssuanceFailure.invalidChart {}
        }
        // A selected singleton keeps independent full corner charts alive.
        let topParent = s.top.curve.source
        let topChild = s.top.curve.chart.selection.child.source
        let topPointChart = try topChild.chart(OriginalLinearChartSelection(lower:0,upper:0),
            limits:.init(remainingSourceDepth:2),using:&a)
        let topPoint = try DefaultOriginalLinearChartIssuer<LineInput,Field>().issue(source:topChild,
            chart:topPointChart,field:f,limits:.init(remainingSourceDepth:2),using:&a)
        let topSelected = try topParent.chart(OriginalParameterImageChartSelection(child:topPoint),
            limits:.init(remainingSourceDepth:2),using:&a)
        let topSingleton = try DefaultOriginalParameterImageChartIssuer<ParameterInput<LineInput>,OriginalLinearChartSelection,Field>()
            .issue(source:topParent,chart:topSelected,field:f,limits:.init(remainingSourceDepth:2),using:&a)
        let singletonChart = try receipt.source.chart(CoonsSelection(bottom:s.bottom,
            top:.init(curve:topSingleton,start:s.top.start,end:s.top.end),left:s.left,right:s.right),
            limits:.init(remainingSourceDepth:2),using:&a)
        let singleton = try CoonsIssuer().issue(source:receipt.source,chart:singletonChart,field:f,
            limits:.init(remainingSourceDepth:2),using:&a)
        try require(try f.compare(singleton.support[0].lower,f.integer(1,using:&a),using:&a) == .equal)
        try require(try f.compare(singleton.support[0].upper,f.integer(1,using:&a),using:&a) == .equal)
        // Corner receipts keep other spans of the same owned boundary.
        let twoSpans = NativeInput(degrees:[1],knots:[[0,0,0.5,1,1]],counts:[3],
            controls:[[0,0,0],[0.5,0,0],[1,0,0]],weights:[1,1,1],periodic:[false])
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:2)
        let bs = try DefaultOriginalSourceBindingIssuer(provider:NativeProvider()).bind(twoSpans,limits:limits,using:&a)
        let c0 = try bs.chart(OriginalBSplineChartSelection(spans:[1]),limits:limits,using:&a)
        let c1 = try bs.chart(OriginalBSplineChartSelection(spans:[2]),limits:limits,using:&a)
        let b0 = try DefaultOriginalBSplineChartIssuer<NativeSnapshot,Field>().issue(source:bs,chart:c0,field:f,limits:limits,using:&a)
        let b1 = try DefaultOriginalBSplineChartIssuer<NativeSnapshot,Field>().issue(source:bs,chart:c1,field:f,limits:limits,using:&a)
        let start = try endpointIssuer.issue(source:bs,curve:b0,localParameter:f.integer(0,using:&a),
            originalParameter:f.integer(0,using:&a),limits:limits,using:&a)
        let end = try endpointIssuer.issue(source:bs,curve:b1,localParameter:f.integer(1,using:&a),
            originalParameter:f.integer(1,using:&a),limits:limits,using:&a)
        let parent = try DefaultOriginalSourceBindingIssuer(provider:CoonsProvider()).bind(
            CoonsInput(bottomBoundary:bs,topBoundary:s.top.curve.source,leftBoundary:s.left.curve.source,
                rightBoundary:s.right.curve.source),limits:limits,using:&a)
        let chart = try parent.chart(CoonsSelection(bottom:.init(curve:b1,start:start,end:end),
            top:s.top,left:s.left,right:s.right),limits:limits,using:&a)
        let partial = try CoonsIssuer().issue(source:parent,chart:chart,field:f,limits:limits,using:&a)
        try require(try f.compare(partial.support[0].lower,f.binary64(exactly:0.5,using:&a),using:&a) == .equal)
        try require(try partial.polynomials.equals(partial.homogeneous[0],
            partial.polynomials.multiplying(partial.polynomials.variable(0,using:&a),partial.denominator,using:&a),using:&a))
        do { _ = try CoonsIssuer().issue(source:parent,chart:chart,field:f,
            limits:.init(remainingSourceDepth:1),using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        var measured = try TraceAdmission();_ = try coonsReceipt(using:&measured)
        var exact = try TraceAdmission(work:measured.work,storage:measured.storageBytes);_ = try coonsReceipt(using:&exact)
        var work = try TraceAdmission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try coonsReceipt(using:&work);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.work))) {}
        var storage = try TraceAdmission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try coonsReceipt(using:&storage);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.storage))) {}
        var entry = try TraceAdmission();entry.base.cancel()
        do { _ = try coonsReceipt(using:&entry);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        var final = try TraceAdmission(cancelAtStorage:measured.storageCalls)
        do { _ = try coonsReceipt(using:&final);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        print("PASS heterogeneous Coons full laws, signed correspondence, uncancelled W, exact corners, other-span endpoint owners and atomic failures")
    }
}
