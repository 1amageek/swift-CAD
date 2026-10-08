#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact Cox-de Boor position laws, using only original source reads and L0/L1.
public struct DefaultOriginalBSplineChartIssuer<Source: OriginalBSplineSourceReading,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalRationalChartIssuing {
    public typealias Selection = OriginalBSplineChartSelection
    public init() {}

    public func issue<A: ExactScalarAdmission & ~Copyable>(
        source: borrowing OriginalSourceBinding<Source>,
        chart: borrowing OriginalSourceChart<Source, Selection>, field: borrowing Field,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalRationalChartReceipt<Source, Selection, Field> {
        do {
            try admission.checkpoint()
            try admission.consumeWork(1)
            try source.require(limits)
            guard source.owns(chart) else { throw OriginalSourceIssuanceFailure.foreignBinding }
            let original = source.original
            let arity = original.parameterCount
            guard (1...2).contains(arity), chart.selection.spans.count == arity else {
                throw OriginalSourceIssuanceFailure.invalidChart
            }
            let ring = try ExactPolynomialDomain(field: copy field, variableCount: arity, using: &admission)
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: arity,
                of: OriginalSourceParameterInterval<Field.Value>.self))
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: arity,
                of: [ExactPolynomial<Field>].self))
            var support: [OriginalSourceParameterInterval<Field.Value>] = []
            var bases: [[ExactPolynomial<Field>]] = []
            support.reserveCapacity(arity); bases.reserveCapacity(arity)
            for axis in 0..<arity {
                try admission.consumeWork(1)
                // FIXME(INCOMPLETE_IMPLEMENTATION): This local Native issuer has no
                // original periodic transport port yet. Independent source issuance
                // must retain exact domain-issued transport before periodic success.
                guard !original.isPeriodic(in: axis) else {
                    throw OriginalSourceIssuanceFailure.unsupportedRepresentation
                }
                let degree = original.degree(in: axis), count = original.controlCount(in: axis)
                let knots = original.knotCount(in: axis), span = chart.selection.spans[axis]
                guard degree > 0, count > degree, span >= degree, span < count else {
                    throw OriginalSourceIssuanceFailure.invalidChart
                }
                let sum = count.addingReportingOverflow(degree)
                let expected = sum.partialValue.addingReportingOverflow(1)
                guard !sum.overflow, !expected.overflow, expected.partialValue == knots else {
                    throw OriginalSourceIssuanceFailure.invalidSource
                }
                try admission.consumeWork(2)
                let lower = original.knot(at: span, in: axis), upper = original.knot(at: span + 1, in: axis)
                guard lower.isFinite, upper.isFinite, lower < upper else {
                    throw OriginalSourceIssuanceFailure.invalidChart
                }
                support.append(.init(lower: try field.binary64(exactly: lower, using: &admission),
                    upper: try field.binary64(exactly: upper, using: &admission)))
                bases.append(try basis(original, axis: axis, span: span, degree: degree,
                    field: field, ring: ring, using: &admission))
            }
            let zero = try ring.zero(using: &admission)
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: ExactPolynomial<Field>.self))
            var homogeneous = [ExactPolynomial<Field>](repeating: zero, count: 4)
            let uSpan = chart.selection.spans[0], uDegree = original.degree(in: 0)
            let vSpan = arity == 2 ? chart.selection.spans[1] : 0
            let vDegree = arity == 2 ? original.degree(in: 1) : 0
            let one = try field.integer(1, using: &admission)
            let unit = try ring.constant(one, using: &admission)
            for j in 0...vDegree {
                for i in 0...uDegree {
                    try admission.consumeWork(1)
                    let u = uSpan - uDegree + i, v = vSpan - vDegree + j
                    let row = v.multipliedReportingOverflow(by: original.controlCount(in: 0))
                    let control = row.partialValue.addingReportingOverflow(u)
                    guard !row.overflow, !control.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                    let weight = try field.binary64(exactly: original.weight(ofControl: control.partialValue), using: &admission)
                    guard try field.sign(of: weight, using: &admission) == .positive else {
                        throw OriginalSourceIssuanceFailure.invalidSource
                    }
                    let tensor = try ring.multiplying(bases[0][i], arity == 2 ? bases[1][j] : unit, using: &admission)
                    for axis in 0..<3 {
                        try admission.consumeWork(1)
                        let coordinate = try field.binary64(exactly: original.coordinate(ofControl: control.partialValue,
                            in: axis), using: &admission)
                        let coefficient = try field.multiplying(coordinate, weight, using: &admission)
                        homogeneous[axis] = try ring.adding(homogeneous[axis],
                            ring.scaled(tensor, by: coefficient, using: &admission), using: &admission)
                    }
                    homogeneous[3] = try ring.adding(homogeneous[3],
                        ring.scaled(tensor, by: weight, using: &admission), using: &admission)
                }
            }
            guard try !ring.isZero(homogeneous[3], using: &admission) else {
                throw OriginalSourceIssuanceFailure.invalidSource
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: arity * 2, of: ExactPolynomial<Field>.self))
            var numerators: [ExactPolynomial<Field>] = [], denominators: [ExactPolynomial<Field>] = []
            numerators.reserveCapacity(arity); denominators.reserveCapacity(arity)
            for axis in 0..<arity {
                try admission.consumeWork(1)
                numerators.append(try ring.variable(axis, using: &admission)); denominators.append(unit)
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                of: OriginalRationalChartReceipt<Source, Selection, Field>.self))
            let result = OriginalRationalChartReceipt(chart: copy chart, field: copy field,
                polynomials: ring, homogeneous: homogeneous, support: support,
                parameterTransport: .init(numerators: numerators, denominators: denominators))
            try admission.checkpoint()
            return result
        } catch { throw .init(preserving: error) }
    }

    private func basis<A: ExactScalarAdmission & ~Copyable>(_ source: Source, axis: Int,
        span: Int, degree: Int, field: borrowing Field, ring: ExactPolynomialDomain<Field>,
        using admission: inout A) throws -> [ExactPolynomial<Field>] {
        let parameter = try ring.variable(axis, using: &admission)
        let one = try field.integer(1, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactPolynomial<Field>.self))
        var current = [try ring.constant(one, using: &admission)]
        for order in 1...degree {
            let width = order.addingReportingOverflow(1)
            guard !width.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: width.partialValue,
                of: ExactPolynomial<Field>.self))
            var next: [ExactPolynomial<Field>] = []; next.reserveCapacity(width.partialValue)
            let previousStart = span - order + 1
            for index in (span - order)...span {
                try admission.consumeWork(1)
                var value = try ring.zero(using: &admission)
                if index >= previousStart {
                    try admission.consumeWork(2)
                    let low = try field.binary64(exactly: source.knot(at: index, in: axis), using: &admission)
                    let high = try field.binary64(exactly: source.knot(at: index + order, in: axis), using: &admission)
                    let difference = try field.subtracting(high, low, using: &admission)
                    let sign = try field.sign(of: difference, using: &admission)
                    guard sign != .negative else { throw OriginalSourceIssuanceFailure.invalidSource }
                    if sign != .zero {
                        let linear = try ring.subtracting(parameter, ring.constant(low, using: &admission), using: &admission)
                        value = try ring.scaled(ring.multiplying(linear, current[index - previousStart], using: &admission),
                            by: field.dividing(one, difference, using: &admission), using: &admission)
                    }
                }
                if index < span {
                    try admission.consumeWork(2)
                    let low = try field.binary64(exactly: source.knot(at: index + 1, in: axis), using: &admission)
                    let high = try field.binary64(exactly: source.knot(at: index + order + 1, in: axis), using: &admission)
                    let difference = try field.subtracting(high, low, using: &admission)
                    let sign = try field.sign(of: difference, using: &admission)
                    guard sign != .negative else { throw OriginalSourceIssuanceFailure.invalidSource }
                    if sign != .zero {
                        let linear = try ring.subtracting(ring.constant(high, using: &admission), parameter, using: &admission)
                        let right = try ring.scaled(ring.multiplying(linear, current[index + 1 - previousStart], using: &admission),
                            by: field.dividing(one, difference, using: &admission), using: &admission)
                        value = try ring.adding(value, right, using: &admission)
                    }
                }
                next.append(value)
            }
            current = next
        }
        return current
    }
}
