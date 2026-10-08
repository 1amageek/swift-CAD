#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalLinearChartIssuer<Source: OriginalLinearSourceReading,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalRationalChartIssuing {
    public typealias Selection = OriginalLinearChartSelection
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        chart: borrowing OriginalSourceChart<Source, Selection>, field: borrowing Field,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalRationalChartReceipt<Source, Selection, Field> {
        do {
            try admission.checkpoint(); try admission.consumeWork(1); try source.require(limits)
            guard source.owns(chart) else { throw OriginalSourceIssuanceFailure.foreignBinding }
            guard chart.selection.lower.isFinite, chart.selection.upper.isFinite,
                chart.selection.lower <= chart.selection.upper else { throw OriginalSourceIssuanceFailure.invalidChart }
            let ring = try ExactPolynomialDomain(field: copy field, variableCount: 1, using: &admission)
            let t = try ring.variable(0, using: &admission)
            let one = try ring.constant(field.integer(1, using: &admission), using: &admission)
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: ExactPolynomial<Field>.self))
            var laws: [ExactPolynomial<Field>] = []; laws.reserveCapacity(4)
            var nonzeroDirection = false
            for axis in 0..<3 {
                try admission.consumeWork(2)
                let origin = try field.binary64(exactly: source.original.originCoordinate(in: axis), using: &admission)
                let direction = try field.binary64(exactly: source.original.directionCoordinate(in: axis), using: &admission)
                if try field.sign(of: direction, using: &admission) != .zero { nonzeroDirection = true }
                laws.append(try ring.adding(ring.constant(origin, using: &admission),
                    ring.scaled(t, by: direction, using: &admission), using: &admission))
            }
            guard nonzeroDirection else { throw OriginalSourceIssuanceFailure.invalidSource }
            laws.append(one)
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalSourceParameterInterval<Field.Value>.self))
            let support = [OriginalSourceParameterInterval(lower:
                try field.binary64(exactly: chart.selection.lower, using: &admission), upper:
                try field.binary64(exactly: chart.selection.upper, using: &admission))]
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ExactPolynomial<Field>.self))
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                of: OriginalRationalChartReceipt<Source, Selection, Field>.self))
            let result = OriginalRationalChartReceipt(chart: copy chart, field: copy field,
                polynomials: ring, homogeneous: laws, support: support,
                parameterTransport: .init(numerators: [t], denominators: [one]))
            try admission.checkpoint(); return result
        } catch { throw .init(preserving: error) }
    }
}
