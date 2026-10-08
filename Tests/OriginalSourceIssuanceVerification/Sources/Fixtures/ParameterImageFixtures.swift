import L0
import L1
import SourceIssuer

extension SourceFixtures {
    struct ParameterInput<C: Sendable>: OriginalParameterImageSourceReading {
        let originalChild: OriginalSourceBinding<C>
        let gains: [(Int,Int)]
        let offsets: [Double]
        let axes: [Int]
        let hasSpatialAction: Bool
        var parameterCount: Int { gains.count }
        func childAxis(forOriginalAxis axis: Int) -> Int { axes[axis] }
        func originalGain<F: ExactScalarArithmetic & ExactScalarOrdering, A: ExactScalarAdmission & ~Copyable>(
            in axis: Int, field: borrowing F, using admission: inout A
        ) throws(OriginalSourceIssuanceFailure) -> F.Value {
            do { return try field.dividing(field.integer(gains[axis].0,using:&admission),
                field.integer(gains[axis].1,using:&admission),using:&admission) }
            catch { throw .scalar(error) }
        }
        func originalOffset<F: ExactScalarArithmetic & ExactScalarOrdering, A: ExactScalarAdmission & ~Copyable>(
            in axis: Int, field: borrowing F, using admission: inout A
        ) throws(OriginalSourceIssuanceFailure) -> F.Value {
            do { return try field.binary64(exactly:offsets[axis],using:&admission) }
            catch { throw .scalar(error) }
        }
        func originalSpatialCoefficient<F: ExactScalarArithmetic & ExactScalarOrdering, A: ExactScalarAdmission & ~Copyable>(
            row: Int, column: Int, field: borrowing F, using admission: inout A
        ) throws(OriginalSourceIssuanceFailure) -> F.Value {
            do { return try field.integer([[1,0,0,1],[0,2,0,-1],[0,0,3,0]][row][column],using:&admission) }
            catch { throw .scalar(error) }
        }
    }
    struct ParameterProvider<C: Sendable>: OriginalSourceSnapshotting {
        func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing ParameterInput<C>,
            limits: OriginalSourceIssuanceLimits, using admission: inout A
        ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<ParameterInput<C>> {
            do { try admission.consumeWork(1) } catch { throw .scalar(error) }
            guard input.gains.count == input.offsets.count, input.gains.count == input.axes.count else { throw .invalidSource }
            return .init(original:copy input,sourceDepth:input.originalChild.sourceDepth+1)
        }
    }
    typealias ParameterReceipt = OriginalRationalChartReceipt<ParameterInput<NativeSnapshot>,
        OriginalParameterImageChartSelection<NativeSnapshot,OriginalBSplineChartSelection,Field>,Field>
    static func parameterReceipt<A: ExactScalarAdmission & ~Copyable>(using admission: inout A) throws -> ParameterReceipt {
        let child = try issue(input(degree:2),using:&admission)
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let source = try DefaultOriginalSourceBindingIssuer(provider:ParameterProvider<NativeSnapshot>()).bind(
            ParameterInput(originalChild:child.source,gains:[(-3,2)],offsets:[0.25],axes:[0],hasSpatialAction:false),
            limits:limits,using:&admission)
        let chart = try source.chart(OriginalParameterImageChartSelection(child:child),limits:limits,using:&admission)
        return try DefaultOriginalParameterImageChartIssuer<ParameterInput<NativeSnapshot>,OriginalBSplineChartSelection,Field>()
            .issue(source:source,chart:chart,field:child.field,limits:limits,using:&admission)
    }
    public static func parameterImageLaws() throws {
        var a = try TraceAdmission()
        let result = try parameterReceipt(using:&a), child = result.chart.selection.child
        let r = result.polynomials,f = result.field,t = try r.variable(0,using:&a)
        for axis in 0..<4 {
            try require(try r.equals(result.homogeneous[axis],r.importing(child.homogeneous[axis],using:&a),using:&a))
        }
        let expectedN = try r.subtracting(t,r.constant(f.binary64(exactly:0.25,using:&a),using:&a),using:&a)
        let expectedD = try r.constant(f.dividing(f.integer(-3,using:&a),f.integer(2,using:&a),using:&a),using:&a)
        try require(try r.equals(result.parameterTransport.numerators[0],expectedN,using:&a))
        try require(try r.equals(result.parameterTransport.denominators[0],expectedD,using:&a))
        for (local,n,d) in [(0,1,6),(1,-1,2)] {
            let coordinates = [try f.integer(local,using:&a)]
            let value = try f.dividing(r.evaluated(result.parameterTransport.numerators[0],at:coordinates,using:&a).value,
                r.evaluated(result.parameterTransport.denominators[0],at:coordinates,using:&a).value,using:&a)
            try require(try f.compare(value,f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a),using:&a) == .equal)
        }
        try require(try f.compare(result.support[0].lower,f.integer(0,using:&a),using:&a) == .equal)
        try require(try f.compare(result.support[0].upper,f.integer(1,using:&a),using:&a) == .equal)
        // Compose another image over the already nonunit child transport.
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:2)
        let parent = try DefaultOriginalSourceBindingIssuer(provider:ParameterProvider<ParameterInput<NativeSnapshot>>()).bind(
            ParameterInput(originalChild:result.source,gains:[(2,3)],offsets:[0.5],axes:[0],hasSpatialAction:false),
            limits:limits,using:&a)
        let chart = try parent.chart(OriginalParameterImageChartSelection(child:result),limits:limits,using:&a)
        let nested = try DefaultOriginalParameterImageChartIssuer<ParameterInput<ParameterInput<NativeSnapshot>>,
            OriginalParameterImageChartSelection<NativeSnapshot,OriginalBSplineChartSelection,Field>,Field>()
            .issue(source:parent,chart:chart,field:f,limits:limits,using:&a)
        let nr = nested.polynomials
        let nestedN = try nr.subtracting(nr.importing(expectedN,using:&a),nr.scaled(nr.importing(expectedD,using:&a),
            by:f.binary64(exactly:0.5,using:&a),using:&a),using:&a)
        let nestedD = try nr.scaled(nr.importing(expectedD,using:&a),by:f.dividing(f.integer(2,using:&a),f.integer(3,using:&a),using:&a),using:&a)
        try require(try nr.equals(nested.parameterTransport.numerators[0],nestedN,using:&a))
        try require(try nr.equals(nested.parameterTransport.denominators[0],nestedD,using:&a))
        try require(nested.source.sourceDepth == 2 && nested.source.original.originalChild.owns(result.chart))
        var measured = try TraceAdmission();_ = try parameterReceipt(using:&measured)
        var exact = try TraceAdmission(work:measured.work,storage:measured.storageBytes);_ = try parameterReceipt(using:&exact)
        var work = try TraceAdmission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try parameterReceipt(using:&work);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.work))) {}
        var storage = try TraceAdmission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try parameterReceipt(using:&storage);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.storage))) {}
        var cancel = try TraceAdmission(cancelAtStorage:measured.storageCalls)
        do { _ = try parameterReceipt(using:&cancel);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        var entry = try TraceAdmission();entry.base.cancel()
        do { _ = try parameterReceipt(using:&entry);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        let issuer = DefaultOriginalParameterImageChartIssuer<ParameterInput<NativeSnapshot>,OriginalBSplineChartSelection,Field>()
        let foreign = try issue(input(degree:2),using:&a)
        let wrong = try result.source.chart(OriginalParameterImageChartSelection(child:foreign),limits:limits,using:&a)
        do { _ = try issuer.issue(source:result.source,chart:wrong,field:f,limits:limits,using:&a);throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.foreignBinding {}
        do { _ = try issuer.issue(source:result.source,chart:result.chart,field:f,limits:.init(remainingSourceDepth:0),using:&a)
            throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        let tensor = NativeInput(degrees:[1,1],knots:[[0,0,1,1],[0,0,1,1]],counts:[2,2],
            controls:[[0,0,0],[1,0,0],[0,1,0],[1,1,1]],weights:[1,2,3,6],periodic:[false,false])
        let surface = try issue(tensor,spans:[1,1],using:&a)
        for axes in [[1,0],[0,0]] {
            let owner = try DefaultOriginalSourceBindingIssuer(provider:ParameterProvider<NativeSnapshot>()).bind(
                ParameterInput(originalChild:surface.source,gains:[(-2,1),(3,1)],offsets:[0.5,0.25],axes:axes,hasSpatialAction:true),
                limits:limits,using:&a)
            let c = try owner.chart(OriginalParameterImageChartSelection(child:surface),limits:limits,using:&a)
            if axes == [0,0] {
                do { _ = try issuer.issue(source:owner,chart:c,field:f,limits:limits,using:&a);throw Failure.incorrectEvidence }
                catch OriginalSourceIssuanceFailure.invalidChart {}
            } else {
                let image = try issuer.issue(source:owner,chart:c,field:f,limits:limits,using:&a),ir = image.polynomials
                let u = try ir.variable(0,using:&a),v = try ir.variable(1,using:&a)
                try require(try ir.equals(image.parameterTransport.numerators[0],
                    ir.subtracting(v,ir.constant(f.binary64(exactly:0.5,using:&a),using:&a),using:&a),using:&a))
                try require(try ir.equals(image.parameterTransport.numerators[1],
                    ir.subtracting(u,ir.constant(f.binary64(exactly:0.25,using:&a),using:&a),using:&a),using:&a))
                for (axis,scale,translation) in [(0,1,1),(1,2,-1),(2,3,0)] {
                    let expected = try ir.adding(ir.scaled(ir.importing(surface.homogeneous[axis],using:&a),
                        by:f.integer(scale,using:&a),using:&a),ir.scaled(ir.importing(surface.denominator,using:&a),
                        by:f.integer(translation,using:&a),using:&a),using:&a)
                    try require(try ir.equals(image.homogeneous[axis],expected,using:&a))
                }
                try require(try ir.equals(image.denominator,ir.importing(surface.denominator,using:&a),using:&a))
            }
        }
        print("PASS signed/nested original parameter transport, nonunit denominators, child-local support, swap/spatial action, provenance and atomic failures")
    }
}
