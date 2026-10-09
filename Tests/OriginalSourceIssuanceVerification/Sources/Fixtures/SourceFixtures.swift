import L0
import L1
import SourceIssuer

public enum SourceFixtures {
    enum Failure: Error { case incorrectEvidence }
    typealias Field = ExactRationalScalarDomain
    typealias Receipt = OriginalRationalChartReceipt<NativeSnapshot, OriginalBSplineChartSelection, Field>

    static func require(_ condition: Bool) throws {
        guard condition else { throw Failure.incorrectEvidence }
    }
    static func input(degree: Int = 1, lower: Double = 0, upper: Double = 1) -> NativeInput {
        let controls: [[Double]] = degree == 1 ? [[0,0,0], [1,0,0]]
            : degree == 2 ? [[0,0,0], [2,1,0], [4,0,0]] : [[0,0,0], [2,0,0], [4,0,0], [6,0,0]]
        return .init(degrees: [degree], knots: [Array(repeating: lower, count: degree + 1)
            + Array(repeating: upper, count: degree + 1)], counts: [degree + 1], controls: controls,
            weights: degree == 1 ? [1,2] : degree == 2 ? [1,2,1] : [1,2,3,4], periodic: [false])
    }
    static func issue<A: ExactScalarAdmission & ~Copyable>(_ input: NativeInput,
        spans: [Int]? = nil, cycles: [Int]? = nil, depth: Int = 4, using admission: inout A) throws -> Receipt {
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth: depth)
        let binding = try DefaultOriginalSourceBindingIssuer(provider: NativeProvider())
            .bind(input, limits: limits, using: &admission)
        let selection = try binding.chart(OriginalBSplineChartSelection(spans: spans ?? input.degrees, cycles: cycles),
            limits: limits, using: &admission)
        return try DefaultOriginalBSplineChartIssuer<NativeSnapshot, Field>().issue(
            source: binding, chart: selection, field: Field(), limits: limits, using: &admission)
    }
    static func polynomial<A: ExactScalarAdmission & ~Copyable>(_ receipt: Receipt,
        terms: [([Int], Int)], using admission: inout A) throws -> ExactPolynomial<Field> {
        var coefficients: [ExactPolynomialTerm<Field.Value>] = []
        for (powers, value) in terms {
            coefficients.append(.init(powers: powers, coefficient: try receipt.field.integer(value, using: &admission)))
        }
        return try receipt.polynomials.polynomial(terms: coefficients, using: &admission)
    }
    static func equal<A: ExactScalarAdmission & ~Copyable>(_ receipt: Receipt, axis: Int,
        terms: [([Int], Int)], using admission: inout A) throws {
        try require(try receipt.polynomials.equals(receipt.homogeneous[axis],
            polynomial(receipt, terms: terms, using: &admission), using: &admission))
    }

    public static func exactLaws() throws {
        var a = try TraceAdmission()
        let linear = try issue(input(), using: &a)
        try equal(linear, axis: 0, terms: [([1],2)], using: &a)
        try equal(linear, axis: 3, terms: [([0],1),([1],1)], using: &a)
        try require(try !linear.polynomials.isZero(linear.denominator, using: &a))
        let quadratic = try issue(input(degree: 2), using: &a)
        try equal(quadratic, axis: 0, terms: [([1],8),([2],-4)], using: &a)
        try equal(quadratic, axis: 1, terms: [([1],4),([2],-4)], using: &a)
        try equal(quadratic, axis: 3, terms: [([0],1),([1],2),([2],-2)], using: &a)
        let cubic = try issue(input(degree: 3), using: &a)
        try equal(cubic, axis: 0, terms: [([1],12),([2],12)], using: &a)
        try equal(cubic, axis: 3, terms: [([0],1),([1],3)], using: &a)
        let nonunit = try issue(input(lower: 2, upper: 5), using: &a)
        let f = nonunit.field, ring = nonunit.polynomials
        let q = try ring.scaled(ring.subtracting(ring.variable(0, using: &a),
            ring.constant(f.integer(2, using: &a), using: &a), using: &a),
            by: f.dividing(f.integer(1, using: &a), f.integer(3, using: &a), using: &a), using: &a)
        try require(try ring.equals(nonunit.homogeneous[0], ring.scaled(q, by: f.integer(2, using: &a), using: &a), using: &a))
        try require(try f.compare(nonunit.support[0].lower, f.integer(2, using: &a), using: &a) == .equal)
        try require(try f.compare(nonunit.support[0].upper, f.integer(5, using: &a), using: &a) == .equal)
        try require(try ring.equals(nonunit.parameterTransport.numerators[0], ring.variable(0, using: &a), using: &a))
        try require(try ring.equals(nonunit.parameterTransport.denominators[0], ring.constant(f.integer(1, using: &a), using: &a), using: &a))
        var subnormal = input(); subnormal.controls[1][0] = Double.leastNonzeroMagnitude
        subnormal.weights[1] = 0.5 // A Double product would erase this exact nonzero coefficient.
        let small = try issue(subnormal, using: &a)
        let exact = try small.field.multiplying(small.field.binary64(exactly: Double.leastNonzeroMagnitude, using: &a),
            small.field.binary64(exactly: 0.5, using: &a), using: &a)
        try require(try small.polynomials.equals(small.homogeneous[0], small.polynomials.scaled(
            small.polynomials.variable(0, using: &a), by: exact, using: &a), using: &a))
        print("PASS original Native degree1/2/3 complete exact coefficients, nonunit transport and subnormal bits")
    }

    public static func selectedSpansAndTensor() throws {
        var a = try TraceAdmission()
        let raw = NativeInput(degrees: [1], knots: [[-1,0,1,2,3]], counts: [3],
            controls: [[0,0,0],[1,0,0],[2,0,0]], weights: [1,2,3], periodic: [false])
        let first = try issue(raw, spans: [1], using: &a), second = try issue(raw, spans: [2], using: &a)
        try equal(first, axis: 0, terms: [([1],2)], using: &a)
        try equal(first, axis: 3, terms: [([0],1),([1],1)], using: &a)
        try equal(second, axis: 0, terms: [([0],-2),([1],4)], using: &a)
        try equal(second, axis: 3, terms: [([0],1),([1],1)], using: &a)
        let repeated = NativeInput(degrees: [2], knots: [[0,0,0,1,1,2,2,2]], counts: [5],
            controls: [[0,0,0],[2,1,0],[4,0,0],[6,-1,0],[8,0,0]], weights: [1,2,1,2,1], periodic: [false])
        let left = try issue(repeated, spans: [2], using: &a), right = try issue(repeated, spans: [4], using: &a)
        try equal(left, axis: 0, terms: [([1],8),([2],-4)], using: &a)
        try equal(right, axis: 0, terms: [([0],-24),([1],40),([2],-12)], using: &a)
        try equal(right, axis: 1, terms: [([0],8),([1],-12),([2],4)], using: &a)
        try equal(right, axis: 3, terms: [([0],-3),([1],6),([2],-2)], using: &a)
        do { _ = try issue(repeated, spans: [3], using: &a); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.invalidChart {}
        let surface = NativeInput(degrees: [2,1], knots: [[0,0,0,1,1,1],[0,0,1,1]], counts: [3,2],
            controls: [[0,0,0],[1,0,0],[2,0,0],[0,1,0],[1,1,1],[2,1,2]],
            weights: [1,2,1,3,6,3], periodic: [false,false])
        let tensor = try issue(surface, using: &a), ring = tensor.polynomials
        let wu = try polynomial(tensor, terms: [([0,0],1),([1,0],2),([2,0],-2)], using: &a)
        let xv = try polynomial(tensor, terms: [([1,0],4),([2,0],-2)], using: &a)
        let wv = try polynomial(tensor, terms: [([0,0],1),([0,1],2)], using: &a)
        let yv = try polynomial(tensor, terms: [([0,1],3)], using: &a)
        for (axis,lhs,rhs) in [(0,xv,wv),(1,wu,yv),(2,xv,yv),(3,wu,wv)] {
            try require(try ring.equals(tensor.homogeneous[axis], ring.multiplying(lhs,rhs,using:&a),using:&a))
        }
        try require(tensor.support.count == 2 && tensor.parameterTransport.numerators.count == 2)
        print("PASS selected nonclamped multi-span laws and complete weighted tensor coefficients")
    }

    public static func ownership() throws {
        var a = try TraceAdmission()
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth: 4)
        let factory = DefaultOriginalSourceBindingIssuer(provider: NativeProvider())
        var raw = input()
        let owner = try factory.bind(raw, limits: limits, using: &a)
        let ownerCopy = owner
        let chart = try owner.chart(OriginalBSplineChartSelection(spans: [1]), limits: limits, using: &a)
        let foreign = try factory.bind(raw, limits: limits, using: &a)
        raw.controls[1][0] = 100; raw.weights[1] = 100
        try require(ownerCopy.owns(chart) && !foreign.owns(chart))
        let issuer = DefaultOriginalBSplineChartIssuer<NativeSnapshot, Field>()
        let receipt = try issuer.issue(source: ownerCopy, chart: chart, field: Field(), limits: limits, using: &a)
        try equal(receipt, axis: 0, terms: [([1],2)], using: &a)
        do {
            _ = try issuer.issue(source: foreign, chart: chart, field: Field(), limits: limits, using: &a)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.foreignBinding {}
        let released: Receipt = try { var local = input(degree: 2)
            let retained = try issue(local, using: &a); local.controls.removeAll(); return retained }()
        try equal(released, axis: 0, terms: [([1],8),([2],-4)], using: &a)
        let unrelated = try ExactPolynomialDomain(field: Field(), variableCount: 1, using: &a)
        do { _ = try unrelated.isZero(receipt.denominator, using: &a); throw Failure.incorrectEvidence }
        catch ExactPolynomialFailure.incompatibleDomain {}
        print("PASS retained source lifetime, COW mutation, binding copy, foreign chart and polynomial owners")
    }

    public static func failures() throws {
        for mode in 0..<5 {
            var bad = input()
            switch mode {
            case 0: bad.weights[0] = 0
            case 1: bad.knots[0][2] = -1
            case 2: bad.controls[0][1] = .infinity
            case 3: bad.controls.removeLast()
            default: bad.degrees[0] = 0
            }
            var a = try TraceAdmission()
            do { _ = try issue(bad, using: &a); throw Failure.incorrectEvidence }
            catch OriginalSourceIssuanceFailure.invalidSource {}
        }
        var a = try TraceAdmission()
        do { _ = try issue(input(), spans: [0], using: &a); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.invalidChart {}
        do { _ = try issue(input(), spans: [], using: &a); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.invalidChart {}
        var periodic = input(); periodic.periodic[0] = true
        do { _ = try issue(periodic, using: &a); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        var deep = input(); deep.sourceDepth = 1
        do { _ = try issue(deep, depth: 0, using: &a); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        let factory = DefaultOriginalSourceBindingIssuer(provider: NativeProvider())
        let owner = try factory.bind(deep, limits: .init(remainingSourceDepth: 1), using: &a)
        let chart = try owner.chart(OriginalBSplineChartSelection(spans: [1]), limits: .init(remainingSourceDepth: 1), using: &a)
        do { _ = try owner.chart(OriginalBSplineChartSelection(spans: [1]), limits: .init(remainingSourceDepth: 0), using: &a)
            throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        do { _ = try DefaultOriginalBSplineChartIssuer<NativeSnapshot, Field>().issue(source: owner, chart: chart,
            field: Field(), limits: .init(remainingSourceDepth: 0), using: &a); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        print("PASS invalid source/chart, unproved periodic law and independently inherited source-depth refusal")
    }

    public static func resources() throws {
        let raw = input(degree: 2)
        var measured = try TraceAdmission()
        _ = try issue(raw, using: &measured)
        let work = measured.work, bytes = measured.storageBytes, final = measured.storageCalls
        var exact = try TraceAdmission(work: work, storage: bytes)
        _ = try issue(raw, using: &exact)
        try require(exact.work == work && exact.storageBytes == bytes && final > 3)
        var lowWork = try TraceAdmission(work: work - 1)
        do { _ = try issue(raw, using: &lowWork); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.work))) {}
        var lowStorage = try TraceAdmission(storage: bytes - 1)
        do { _ = try issue(raw, using: &lowStorage); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(.storage))) {}
        for ordinal in [1,final] {
            var cancelled = try TraceAdmission(cancelAtStorage: ordinal)
            do { _ = try issue(raw, using: &cancelled); throw Failure.incorrectEvidence }
            catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
            catch OriginalSourceIssuanceFailure.polynomial(.scalar(.cancelled)) {}
            try require(cancelled.storageCalls == ordinal)
        }
        var entry = try TraceAdmission(); entry.base.cancel()
        do { _ = try issue(raw, using: &entry); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        try require(entry.work == 0 && entry.storageBytes == 0)
        for axis in [ExactScalarRootAxis.value, .coefficient] {
            var rejection = try TraceAdmission(rejectDepth: axis)
            do { _ = try issue(raw, using: &rejection); throw Failure.incorrectEvidence }
            catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(let resource))) {
                try require(resource == (axis == .value ? .valueDepth : .coefficientDepth))
            }
        }
        print("PASS exact cumulative work/storage boundary, entry/final cancellation and caller depth rejection")
        print("MEASURE quadratic work=\(work) generatedBytes=\(bytes) storageAdmissions=\(final)")
    }

    public static func runAll() throws {
        try exactLaws(); try selectedSpansAndTensor(); try periodicLaws(); try implicitImages()
        try ownership(); try failures(); try resources()
        try physicalAngleCoefficients(); try physicalAngleResources(); try coneImages(); try ruledLaws(); try spatialLaws(); try parameterImageLaws(); try coonsLaws(); try endpointDecisionDepths(); try retainedRootExtensions(); try directedTraversalLaws(); try scalarTransport()
        try revolutionLaws()
        try offsetLaws()
        print("ORIGINAL_SOURCE_ISSUANCE_PROOF_OK")
    }
}
