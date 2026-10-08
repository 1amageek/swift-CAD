#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Composes original parameter correspondence while keeping certified child variables.
public struct DefaultOriginalParameterImageChartIssuer<Source: OriginalParameterImageSourceReading,
    ChildSelection: Sendable, Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>:
    OriginalRationalChartIssuing where Field.Source == Field.Value {
    public typealias Selection = OriginalParameterImageChartSelection<Source.Child, ChildSelection, Field>
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        chart: borrowing OriginalSourceChart<Source, Selection>, field: borrowing Field,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalRationalChartReceipt<Source, Selection, Field> {
        do {
            try admission.checkpoint(); try admission.consumeWork(1); try source.require(limits)
            guard source.owns(chart), source.original.originalChild.owns(chart.selection.child.chart) else {
                throw OriginalSourceIssuanceFailure.foreignBinding
            }
            guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            try chart.selection.child.admitProof(using: &admission)
            let child = chart.selection.child, count = source.original.parameterCount
            try child.source.require(.init(remainingSourceDepth: limits.remainingSourceDepth - 1))
            guard (count == 1 || count == 2), child.support.count == count,
                child.polynomials.variableCount == count, child.homogeneous.count == 4,
                child.parameterTransport.numerators.count == count,
                child.parameterTransport.denominators.count == count else {
                throw OriginalSourceIssuanceFailure.invalidChart
            }
            for axis in 0..<count {
                try admission.consumeWork(1)
                let k = source.original.childAxis(forOriginalAxis: axis)
                guard k >= 0, k < count else { throw OriginalSourceIssuanceFailure.invalidChart }
                for prior in 0..<axis {
                    try admission.consumeWork(1)
                    guard k != source.original.childAxis(forOriginalAxis: prior) else {
                        throw OriginalSourceIssuanceFailure.invalidChart
                    }
                }
            }
            let ring = try ExactPolynomialDomain(field: copy field, variableCount: count, using: &admission)
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: ExactPolynomial<Field>.self))
            var h: [ExactPolynomial<Field>] = []; h.reserveCapacity(4)
            for law in child.homogeneous { h.append(try ring.importing(law, using: &admission)) }
            guard try !ring.isZero(h[3], using: &admission) else { throw OriginalSourceIssuanceFailure.invalidSource }
            if source.original.hasSpatialAction {
                try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: ExactPolynomial<Field>.self))
                var transformed: [ExactPolynomial<Field>] = []; transformed.reserveCapacity(4)
                for row in 0..<3 {
                    var sum = try ring.zero(using: &admission)
                    for column in 0..<4 {
                        try admission.consumeWork(1)
                        let coefficient = try source.original.originalSpatialCoefficient(
                            row: row, column: column, field: field, using: &admission)
                        sum = try ring.adding(sum, ring.scaled(h[column], by: coefficient, using: &admission), using: &admission)
                    }
                    transformed.append(sum)
                }
                transformed.append(h[3]); h = transformed
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: OriginalSourceParameterInterval<Field.Value>.self))
            var support: [OriginalSourceParameterInterval<Field.Value>] = []; support.reserveCapacity(count)
            for interval in child.support {
                support.append(.init(lower: try field.importing(interval.lower, using: &admission),
                    upper: try field.importing(interval.upper, using: &admission)))
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: ExactPolynomial<Field>.self))
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: ExactPolynomial<Field>.self))
            var numerators: [ExactPolynomial<Field>] = [], denominators: [ExactPolynomial<Field>] = []
            numerators.reserveCapacity(count); denominators.reserveCapacity(count)
            for axis in 0..<count {
                try admission.consumeWork(1)
                let k = source.original.childAxis(forOriginalAxis: axis)
                let gain = try source.original.originalGain(in: axis, field: field, using: &admission)
                guard try field.sign(of: gain, using: &admission) != .zero else { throw OriginalSourceIssuanceFailure.invalidSource }
                let offset = try source.original.originalOffset(in: axis, field: field, using: &admission)
                let n = try ring.importing(child.parameterTransport.numerators[k], using: &admission)
                let d = try ring.importing(child.parameterTransport.denominators[k], using: &admission)
                guard try !ring.isZero(d, using: &admission) else { throw OriginalSourceIssuanceFailure.invalidChart }
                numerators.append(try ring.subtracting(n, ring.scaled(d, by: offset, using: &admission), using: &admission))
                denominators.append(try ring.scaled(d, by: gain, using: &admission))
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                of: OriginalRationalChartReceipt<Source, Selection, Field>.self))
            let result = OriginalRationalChartReceipt(chart: copy chart, field: copy field,
                polynomials: ring, homogeneous: h, support: support,
                parameterTransport: .init(numerators: numerators, denominators: denominators), proofDepth: child.proofDepth)
            try admission.checkpoint(); return result
        } catch { throw .init(preserving: error) }
    }
}
