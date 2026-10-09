import L0
import L1
import SourceIssuer

extension SourceFixtures {
    struct SpatialInput<C: Sendable>: OriginalSpatialSourceReading {
        let originalChild: OriginalSourceBinding<NativeSnapshot>
        let coefficients: [C]
        func spatialCoefficient(row: Int, column: Int) -> C { coefficients[row * 4 + column] }
    }
    struct SpatialProvider<C: Sendable>: OriginalSourceSnapshotting {
        func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing SpatialInput<C>,
            limits: OriginalSourceIssuanceLimits, using admission: inout A
        ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<SpatialInput<C>> {
            do { try admission.consumeWork(1) } catch { throw .scalar(error) }
            guard input.coefficients.count == 12 else { throw .invalidSource }
            return .init(original: copy input, sourceDepth: 1)
        }
    }
    typealias SpatialReceipt = OriginalRationalChartReceipt<SpatialInput<Field.Value>,
        OriginalSpatialChartSelection<NativeSnapshot, OriginalBSplineChartSelection, Field>, Field>
    static func spatialReceipt<A: ExactScalarAdmission & ~Copyable>(using admission: inout A) throws -> SpatialReceipt {
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth: 1)
        let child = try issue(input(), using: &admission), f = child.field
        var coefficients: [Field.Value] = []
        for value in [2,0,0,3, 0,-1,0,4, 0,0,0,5] { coefficients.append(try f.integer(value, using: &admission)) }
        let source = try DefaultOriginalSourceBindingIssuer(provider: SpatialProvider<Field.Value>()).bind(
            SpatialInput(originalChild: child.source, coefficients: coefficients), limits: limits, using: &admission)
        let chart = try source.chart(OriginalSpatialChartSelection(child: child), limits: limits, using: &admission)
        return try DefaultOriginalSpatialChartIssuer<SpatialInput<Field.Value>,OriginalBSplineChartSelection,Field>()
            .issue(source: source, chart: chart, field: f, limits: limits, using: &admission)
    }
    public static func spatialLaws() throws {
        var a = try TraceAdmission()
        let receipt = try spatialReceipt(using: &a), r = receipt.polynomials, f = receipt.field
        let child = receipt.chart.selection.child
        for (row, factors) in [(0,[2,0,0,3]), (1,[0,-1,0,4]), (2,[0,0,0,5])] {
            var expected = try r.zero(using: &a)
            for column in 0..<4 {
                expected = try r.adding(expected, r.scaled(r.importing(child.homogeneous[column], using: &a),
                    by: f.integer(factors[column], using: &a), using: &a), using: &a)
            }
            try require(try r.equals(receipt.homogeneous[row], expected, using: &a))
        }
        try require(try r.equals(receipt.denominator, r.importing(child.denominator, using: &a), using: &a))
        try require(try f.compare(receipt.support[0].lower, child.support[0].lower, using: &a) == .equal)
        try require(try f.compare(receipt.support[0].upper, child.support[0].upper, using: &a) == .equal)
        try require(try r.equals(receipt.parameterTransport.numerators[0],
            r.importing(child.parameterTransport.numerators[0], using: &a), using: &a))
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth: 1)
        let foreign = try issue(input(), using: &a)
        let wrong = try receipt.source.chart(OriginalSpatialChartSelection(child: foreign), limits: limits, using: &a)
        let issuer = DefaultOriginalSpatialChartIssuer<SpatialInput<Field.Value>,OriginalBSplineChartSelection,Field>()
        do { _ = try issuer.issue(source: receipt.source, chart: wrong, field: f, limits: limits, using: &a)
            throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.foreignBinding {}
        do { _ = try issuer.issue(source: receipt.source, chart: receipt.chart, field: f,
            limits: .init(remainingSourceDepth: 0), using: &a); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        var measured = try TraceAdmission(); _ = try spatialReceipt(using: &measured)
        var exact = try TraceAdmission(work: measured.work, storage: measured.storageBytes)
        _ = try spatialReceipt(using: &exact)
        var work = try TraceAdmission(work: measured.work - 1, storage: measured.storageBytes)
        do { _ = try spatialReceipt(using: &work); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.work))) {}
        var storage = try TraceAdmission(work: measured.work, storage: measured.storageBytes - 1)
        do { _ = try spatialReceipt(using: &storage); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.storage))) {}
        var cancel = try TraceAdmission(cancelAtStorage: measured.storageCalls)
        do { _ = try spatialReceipt(using: &cancel); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        var entry = try TraceAdmission(); entry.base.cancel()
        do { _ = try spatialReceipt(using: &entry); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        // A genuinely transcendental coefficient exercises the generic action,
        // independent of the rational fixture and without rounded substitution.
        let angle = try OriginalPhysicalAngleScalarDomain(originalRadians: 1, using: &a)
        let binding = try DefaultOriginalSourceBindingIssuer(provider: NativeProvider()).bind(
            input(), limits: limits, using: &a)
        let selected = try binding.chart(OriginalBSplineChartSelection(spans: [1]), limits: limits, using: &a)
        let curve = try DefaultOriginalBSplineChartIssuer<NativeSnapshot,OriginalPhysicalAngleScalarDomain>().issue(
            source: binding, chart: selected, field: angle, limits: limits, using: &a)
        let z = try angle.integer(0, using: &a), o = try angle.integer(1, using: &a), s = try angle.sine(using: &a)
        let parent = try DefaultOriginalSourceBindingIssuer(provider: SpatialProvider<OriginalPhysicalAngleValue>()).bind(
            SpatialInput(originalChild: binding, coefficients: [s,z,z,o, z,o,z,z, z,z,o,z]), limits: limits, using: &a)
        let chart = try parent.chart(OriginalSpatialChartSelection(child: curve), limits: limits, using: &a)
        let operation = DefaultOriginalSpatialChartIssuer<SpatialInput<OriginalPhysicalAngleValue>,OriginalBSplineChartSelection,OriginalPhysicalAngleScalarDomain>()
        let image = try operation.issue(source: parent, chart: chart, field: angle, limits: limits, using: &a)
        let expected = try image.polynomials.adding(image.polynomials.scaled(
            image.polynomials.importing(curve.homogeneous[0], using: &a), by: s, using: &a),
            image.polynomials.importing(curve.denominator, using: &a), using: &a)
        try require(try image.polynomials.equals(image.homogeneous[0], expected, using: &a))
        let other = try OriginalPhysicalAngleScalarDomain(originalRadians: 1, using: &a)
        do { _ = try operation.issue(source: parent, chart: chart, field: other, limits: limits, using: &a)
            throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.incompatibleDomain)) {}
        try transportedSpatialCoefficients()
        print("PASS original spatial homogeneous action, exact rational/transcendental coefficients, W/support/transport retention and atomic failures")
    }

    static func transportedSpatialCoefficients() throws {
        var a = try TraceAdmission()
        let raw = try retainedRootBinding(try selectedRoot(2), using: &a)
        let alpha = try raw.generator(using: &a)
        let z = try raw.integer(0, using: &a), o = try raw.integer(1, using: &a)
        let original = [alpha,z,z,o, z,o,z,z, z,z,o,z]
        let destination = try OriginalExactScalarDomain(maximumValueDepth: 32,
            maximumCoefficientDepth: 32, using: &a)
        let transfer = try DefaultOriginalScalarTransporter().transfer(original, into: destination, using: &a)
        let f = transfer.field, limits = try OriginalSourceIssuanceLimits(remainingSourceDepth: 1)
        let childSource = try DefaultOriginalSourceBindingIssuer(provider: NativeProvider()).bind(input(), limits: limits, using: &a)
        let childChart = try childSource.chart(OriginalBSplineChartSelection(spans: [1]), limits: limits, using: &a)
        let child = try DefaultOriginalBSplineChartIssuer<NativeSnapshot, OriginalExactScalarDomain>().issue(
            source: childSource, chart: childChart, field: f, limits: limits, using: &a)
        let source = try DefaultOriginalSourceBindingIssuer(provider: SpatialProvider<OriginalExactScalar>()).bind(
            SpatialInput(originalChild: childSource, coefficients: original), limits: limits, using: &a)
        let chart = try source.chart(OriginalSpatialChartSelection(child: child), limits: limits, using: &a)
        let issuer = DefaultOriginalSpatialChartIssuer<SpatialInput<OriginalExactScalar>, OriginalBSplineChartSelection, OriginalExactScalarDomain>()
        do {
            _ = try issuer.issue(source: source, chart: chart, field: f, limits: limits, using: &a)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.scalar(.incompatibleDomain) {}
        let result = try issuer.issue(source: source, chart: chart, field: f,
            coefficients: OriginalTransportedSourceCoefficientImporter(transfer: transfer), limits: limits, using: &a)
        try require(source.owns(result.chart) && childSource.owns(result.chart.selection.child.chart))
        let r = result.polynomials
        let expected = try r.adding(r.scaled(r.importing(child.homogeneous[0], using: &a),
            by: transfer.values[0], using: &a), r.importing(child.denominator, using: &a), using: &a)
        try require(try r.equals(result.homogeneous[0], expected, using: &a))
        let unrelated = try retainedRootBinding(try selectedRoot(3), using: &a)
        let wrongTransfer = try DefaultOriginalScalarTransporter().transfer([unrelated.generator(using: &a)], into: destination, using: &a)
        do {
            _ = try issuer.issue(source: source, chart: chart, field: f,
                coefficients: OriginalTransportedSourceCoefficientImporter(transfer: wrongTransfer), limits: limits, using: &a)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.scalar(.incompatibleDomain) {}
    }
}
