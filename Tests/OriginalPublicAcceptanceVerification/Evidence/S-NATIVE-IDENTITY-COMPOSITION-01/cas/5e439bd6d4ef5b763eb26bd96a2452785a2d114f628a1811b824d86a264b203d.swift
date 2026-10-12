#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Uses the exact affine inverse of retained normalized traversal laws.
public struct DefaultOriginalFiniteCoonsBoundaryPreparer<Source: Sendable, Selection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalFiniteCoonsBoundaryPreparing
    where Field.Source == Field.Value {
    public init() {}
    public func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        curves: borrowing [OriginalRationalChartReceipt<Source, Selection, Field>], field: borrowing Field,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> [OriginalCoonsBoundarySelection<Source, Selection, Field>] {
        do {
            try admission.checkpoint(); try source.require(limits)
            let start = try endpoint(0, source: source, curves: curves, field: field, limits: limits, using: &admission)
            let end = try endpoint(1, source: source, curves: curves, field: field, limits: limits, using: &admission)
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: curves.count,
                of: OriginalCoonsBoundarySelection<Source, Selection, Field>.self))
            var result: [OriginalCoonsBoundarySelection<Source, Selection, Field>] = []; result.reserveCapacity(curves.count)
            for index in curves.indices {
                try admission.consumeWork(1)
                guard source.owns(curves[index].chart) else { throw OriginalSourceIssuanceFailure.foreignBinding }
                result.append(.init(curve: curves[index], start: start, end: end))
            }
            try admission.checkpoint(); return result
        } catch { throw .init(preserving: error) }
    }
    private func endpoint<A: ExactScalarAdmission & ~Copyable>(_ station: Int,
        source: borrowing OriginalSourceBinding<Source>, curves: borrowing [OriginalRationalChartReceipt<Source, Selection, Field>],
        field: borrowing Field, limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws -> OriginalCurveEndpointReceipt<Source, Selection, Field> {
        let original = try field.integer(station, using: &admission)
        for index in curves.indices {
            try admission.consumeWork(1)
            guard source.owns(curves[index].chart) else { throw OriginalSourceIssuanceFailure.foreignBinding }
            let range = try OriginalFiniteCurveChartRange<Field>.prepare(curves[index], field: field, using: &admission)
            if try field.compare(original, range.lower, using: &admission) != .less,
                try field.compare(original, range.upper, using: &admission) != .greater {
                let local = try field.dividing(field.subtracting(original, range.offset, using: &admission), range.gain, using: &admission)
                return try DefaultOriginalCurveEndpointIssuer<Source, Selection, Field>().issue(source: source,
                    curve: curves[index], localParameter: local, originalParameter: original,
                    limits: limits, using: &admission)
            }
        }
        throw OriginalSourceIssuanceFailure.invalidChart
    }
}
