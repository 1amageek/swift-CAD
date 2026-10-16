#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Evaluates an admitted closed endpoint without extrapolation or a root query.
public struct DefaultOriginalCurveEndpointIssuer<Source: Sendable, Selection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalCurveEndpointIssuing
    where Field.Source == Field.Value {
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        curve: borrowing OriginalRationalChartReceipt<Source, Selection, Field>,
        localParameter: borrowing Field.Value, originalParameter: borrowing Field.Value,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalCurveEndpointReceipt<Source, Selection, Field> {
        let source = copy source, curve = copy curve
        let localParameter = copy localParameter, originalParameter = copy originalParameter
        do {
            return try admission.withProofScope { usage in
                try Self.evaluate(source: source, curve: curve, localParameter: localParameter,
                    originalParameter: originalParameter, limits: limits, using: &usage)
            }
        } catch { throw .init(preserving: error) }
    }
    private static func evaluate<A: ExactScalarAdmission & ~Copyable>(
        source: borrowing OriginalSourceBinding<Source>, curve: borrowing OriginalRationalChartReceipt<Source, Selection, Field>,
        localParameter: borrowing Field.Value, originalParameter: borrowing Field.Value,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws -> OriginalCurveEndpointReceipt<Source, Selection, Field> {
            try admission.checkpoint(); try admission.consumeWork(1); try source.require(limits)
            guard source.owns(curve.chart) else { throw OriginalSourceIssuanceFailure.foreignBinding }
            guard curve.polynomials.variableCount == 1, curve.support.count == 1,
                curve.homogeneous.count == 4, curve.parameterTransport.numerators.count == 1,
                curve.parameterTransport.denominators.count == 1 else { throw OriginalSourceIssuanceFailure.invalidChart }
            try curve.admitProof(using: &admission)
            let f = curve.field, ring = curve.polynomials
            let local = try f.importing(localParameter, using: &admission)
            let original = try f.importing(originalParameter, using: &admission)
            guard try f.compare(local, curve.support[0].lower, using: &admission) != .less,
                try f.compare(local, curve.support[0].upper, using: &admission) != .greater else {
                throw OriginalSourceIssuanceFailure.invalidChart
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Field.Value.self))
            let coordinates = [local]
            var valueDepth = 0, coefficientDepth = 0
            func evaluate(_ polynomial: ExactPolynomial<Field>, _ usage: inout A) throws -> Field.Value {
                let result = try ring.evaluated(polynomial, at: coordinates, using: &usage)
                valueDepth = max(valueDepth, result.depth.value)
                coefficientDepth = max(coefficientDepth, result.depth.coefficient)
                return result.value
            }
            let n = try evaluate(curve.parameterTransport.numerators[0], &admission)
            let d = try evaluate(curve.parameterTransport.denominators[0], &admission)
            guard try f.sign(of: d, using: &admission) != .zero,
                try f.compare(n, f.multiplying(original, d, using: &admission), using: &admission) == .equal else {
                throw OriginalSourceIssuanceFailure.invalidChart
            }
            let w = try evaluate(curve.homogeneous[3], &admission)
            guard try f.sign(of: w, using: &admission) != .zero else { throw OriginalSourceIssuanceFailure.invalidChart }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Field.Value.self))
            var xyz: [Field.Value] = []; xyz.reserveCapacity(3)
            for axis in 0..<3 {
                try admission.consumeWork(1)
                xyz.append(try f.dividing(evaluate(curve.homogeneous[axis], &admission), w, using: &admission))
            }
            try admission.admitDepth(value: valueDepth, coefficient: coefficientDepth)
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                of: OriginalCurveEndpointReceipt<Source, Selection, Field>.self))
            let result = OriginalCurveEndpointReceipt(curve: copy curve, localParameter: local,
                originalParameter: original, position: xyz,
                depth: try admission.depth)
            try admission.checkpoint(); return result
    }
}
