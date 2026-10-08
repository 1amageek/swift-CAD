#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Reuses the authored common-U/linear-V formula for arbitrary certified rational children.
public struct DefaultOriginalRuledChartIssuer<Source: OriginalRuledSourceReading,
    FirstSelection: Sendable, SecondSelection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalRationalChartIssuing
    where Field.Source == Field.Value {
    public typealias Selection = OriginalRuledChartSelection<Source.First, FirstSelection,
        Source.Second, SecondSelection, Field>
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        chart: borrowing OriginalSourceChart<Source, Selection>, field: borrowing Field,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalRationalChartReceipt<Source, Selection, Field> {
        do {
            try admission.checkpoint(); try admission.consumeWork(1); try source.require(limits)
            guard source.owns(chart), source.original.firstBoundary.owns(chart.selection.first.chart),
                source.original.secondBoundary.owns(chart.selection.second.chart) else {
                throw OriginalSourceIssuanceFailure.foreignBinding
            }
            guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            let children = try OriginalSourceIssuanceLimits(remainingSourceDepth: limits.remainingSourceDepth - 1)
            try chart.selection.first.source.require(children); try chart.selection.second.source.require(children)
            try chart.selection.first.admitProof(using: &admission)
            try chart.selection.second.admitProof(using: &admission)
            let first = chart.selection.first, second = chart.selection.second
            guard first.support.count == 1, second.support.count == 1,
                first.homogeneous.count == 4, second.homogeneous.count == 4,
                first.parameterTransport.numerators.count == 1, first.parameterTransport.denominators.count == 1,
                second.parameterTransport.numerators.count == 1, second.parameterTransport.denominators.count == 1,
                source.original.originalLowerU.isFinite, source.original.originalUpperU.isFinite,
                source.original.originalLowerU < source.original.originalUpperU else {
                throw OriginalSourceIssuanceFailure.invalidChart
            }
            let ring = try ExactPolynomialDomain(field: copy field, variableCount: 2, using: &admission)
            let u = try ring.variable(0, using: &admission), v = try ring.variable(1, using: &admission)
            let unit = try ring.constant(field.integer(1, using: &admission), using: &admission)
            let vm = try ring.subtracting(unit, v, using: &admission)
            let n1 = try OriginalRuledLawImport.curve(first.parameterTransport.numerators[0], into: ring, field: field, using: &admission)
            let d1 = try OriginalRuledLawImport.curve(first.parameterTransport.denominators[0], into: ring, field: field, using: &admission)
            let n2 = try OriginalRuledLawImport.curve(second.parameterTransport.numerators[0], into: ring, field: field, using: &admission)
            let d2 = try OriginalRuledLawImport.curve(second.parameterTransport.denominators[0], into: ring, field: field, using: &admission)
            guard try ring.equals(n1, ring.multiplying(u, d1, using: &admission), using: &admission),
                try ring.equals(n2, ring.multiplying(u, d2, using: &admission), using: &admission),
                try !ring.isZero(d1, using: &admission), try !ring.isZero(d2, using: &admission) else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            var lower = try field.binary64(exactly: source.original.originalLowerU, using: &admission)
            var upper = try field.binary64(exactly: source.original.originalUpperU, using: &admission)
            for index in 0..<2 {
                let support = index == 0 ? first.support[0] : second.support[0]
                let lo = try field.importing(support.lower, using: &admission)
                let hi = try field.importing(support.upper, using: &admission)
                if try field.compare(lo, lower, using: &admission) == .greater { lower = lo }
                if try field.compare(hi, upper, using: &admission) == .less { upper = hi }
            }
            guard try field.compare(lower, upper, using: &admission) != .greater else {
                throw OriginalSourceIssuanceFailure.invalidChart
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 8, of: ExactPolynomial<Field>.self))
            var a: [ExactPolynomial<Field>] = [], b: [ExactPolynomial<Field>] = []
            a.reserveCapacity(4); b.reserveCapacity(4)
            for axis in 0..<4 {
                a.append(try OriginalRuledLawImport.curve(first.homogeneous[axis], into: ring, field: field, using: &admission))
                b.append(try OriginalRuledLawImport.curve(second.homogeneous[axis], into: ring, field: field, using: &admission))
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: ExactPolynomial<Field>.self))
            var laws: [ExactPolynomial<Field>] = []; laws.reserveCapacity(4)
            for axis in 0..<3 {
                let left = try ring.multiplying(ring.multiplying(a[axis], b[3], using: &admission), vm, using: &admission)
                let right = try ring.multiplying(ring.multiplying(b[axis], a[3], using: &admission), v, using: &admission)
                laws.append(try ring.adding(left, right, using: &admission))
            }
            laws.append(try ring.multiplying(a[3], b[3], using: &admission))
            // Retain parameter-correspondence guards even for an identity quotient.
            // They cannot be cancelled merely because numerator == U * denominator.
            if try !ring.equals(d1, unit, using: &admission) || !ring.equals(d2, unit, using: &admission) {
                let guardFactor = try ring.multiplying(d1, d2, using: &admission)
                for axis in 0..<4 {
                    laws[axis] = try ring.multiplying(laws[axis], guardFactor, using: &admission)
                }
            }
            guard try !ring.isZero(laws[3], using: &admission) else { throw OriginalSourceIssuanceFailure.invalidSource }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: OriginalSourceParameterInterval<Field.Value>.self))
            let support = [OriginalSourceParameterInterval(lower: lower, upper: upper),
                OriginalSourceParameterInterval(lower: try field.integer(0, using: &admission),
                    upper: try field.integer(1, using: &admission))]
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: ExactPolynomial<Field>.self))
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                of: OriginalRationalChartReceipt<Source, Selection, Field>.self))
            let inherited = try ExactScalarDepth(value: max(first.proofDepth?.value ?? 0, second.proofDepth?.value ?? 0),
                coefficient: max(first.proofDepth?.coefficient ?? 0, second.proofDepth?.coefficient ?? 0))
            let result = OriginalRationalChartReceipt(chart: copy chart, field: copy field,
                polynomials: ring, homogeneous: laws, support: support,
                parameterTransport: .init(numerators: [u, v], denominators: [unit, unit]), proofDepth: inherited)
            try admission.checkpoint(); return result
        } catch { throw .init(preserving: error) }
    }
}
