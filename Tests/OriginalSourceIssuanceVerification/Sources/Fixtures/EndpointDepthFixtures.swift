import L0
import L1
import SourceIssuer

/// Exercises decision depths that are absent from otherwise rational coefficients.
struct EndpointDecisionField: ExactScalarArithmetic, ExactScalarOrdering, ExactScalarImporting {
    typealias Value = ExactRationalScalarDomain.Value
    typealias Source = Value
    let base = ExactRationalScalarDomain()
    func integer<I: BinaryInteger, A: ExactScalarAdmission & ~Copyable>(_ source: I, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try base.integer(source, using: &admission)
    }
    func binary64<A: ExactScalarAdmission & ~Copyable>(exactly source: Double, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try base.binary64(exactly: source, using: &admission)
    }
    func importing<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing Source, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try base.importing(source, using: &admission)
    }
    func negated<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Value, using admission: inout A) throws(ExactScalarFailure) -> Value {
        try base.negated(value, using: &admission)
    }
    func adding<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value { try base.adding(lhs, rhs, using: &admission) }
    func subtracting<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value { try base.subtracting(lhs, rhs, using: &admission) }
    func multiplying<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value { try base.multiplying(lhs, rhs, using: &admission) }
    func dividing<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> Value { try base.dividing(lhs, rhs, using: &admission) }
    func sign<A: ExactScalarAdmission & ~Copyable>(of value: borrowing Value, using admission: inout A)
    throws(ExactScalarFailure) -> ExactSign {
        try admission.admitDepth(value: 3, coefficient: 5)
        return try base.sign(of: value, using: &admission)
    }
    func compare<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Value, _ rhs: borrowing Value,
        using admission: inout A) throws(ExactScalarFailure) -> ExactOrder {
        try admission.admitDepth(value: 3, coefficient: 5)
        return try base.compare(lhs, rhs, using: &admission)
    }
}

extension SourceFixtures {
    public static func endpointDecisionDepths() throws {
        var a = try TraceAdmission()
        let f = EndpointDecisionField(),limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let source = try DefaultOriginalSourceBindingIssuer(provider:LineProvider()).bind(
            LineInput(origin:[0,0,0],direction:[1,0,0]),limits:limits,using:&a)
        let chart = try source.chart(OriginalLinearChartSelection(lower:0,upper:1),limits:limits,using:&a)
        let curve = try DefaultOriginalLinearChartIssuer<LineInput,EndpointDecisionField>().issue(
            source:source,chart:chart,field:f,limits:limits,using:&a)
        let endpoint = try DefaultOriginalCurveEndpointIssuer<LineInput,OriginalLinearChartSelection,EndpointDecisionField>()
            .issue(source:source,curve:curve,localParameter:f.integer(0,using:&a),
                originalParameter:f.integer(0,using:&a),limits:limits,using:&a)
        try require(endpoint.depth.value == 3 && endpoint.depth.coefficient == 5)
        for axis in [ExactScalarRootAxis.value,.coefficient] {
            var strict = ExactScalarLedger(limits:try .init(work:20_000_000,storageBytes:134_217_728,
                valueDepth:axis == .value ? 2 : 3,coefficientDepth:axis == .coefficient ? 4 : 5))
            do { try strict.admitDepth(value:endpoint.depth.value,coefficient:endpoint.depth.coefficient)
                throw Failure.incorrectEvidence }
            catch ExactScalarFailure.resourceLimit(let resource) {
                try require(resource == (axis == .value ? .valueDepth : .coefficientDepth))
            }
        }
        print("PASS endpoint decision-only value/coefficient depths survive otherwise depth-zero rational laws")
    }
}
