#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
#endif

/// Converts laws once and preserves all transport guards in unreduced homogeneous W.
public struct DefaultOriginalIssuedMapCompiler<Source: Sendable, Selection: Sendable>: OriginalIssuedMapCompiling {
    public typealias Base = OriginalExactScalarDomain
    public typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Cells = ExactRealCellDomain<Base>
    typealias Domain = ExactParametricRelationDomain<Base, Cells, ExactRealTopology<Base>>
    public init() {}
    public func compile<A: ExactScalarAdmission & ~Copyable>(
        cover: borrowing OriginalIssuedDomainCover<Source, Selection, Base>,
        field: borrowing Field, coefficientTransfer: OriginalScalarTransferReceipt? = nil, maximumMaps: Int, using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedMapPreparation<Source, Selection> {
        do {
            try admission.checkpoint()
            // Empty preparation still binds the caller's original coefficient policy.
            _ = try field.importingBase(cover.coverage.request.frame.scalarField.integer(0, using: &admission), using: &admission)
            guard maximumMaps >= 0 else { throw NativeExactRelationFailure.invalidDomain }
            let domain = Domain(cells: Cells.self, topology: .init(cells: Cells.self))
            let roots = try ExactRealRootDomain(field: copy field, using: &admission)
            var result: [OriginalIssuedSelectedMap] = []
            for chartIndex in cover.charts.indices {
                try admission.consumeWork(1)
                let chart = cover.charts[chartIndex], law = cover.laws[chart.lawIndex]
                try law.admitProof(using: &admission)
                let n = chart.selectedLocal.arity
                guard (1...2).contains(n), law.homogeneous.count == 4 else {
                    throw NativeExactRelationFailure.invalidDomain
                }
                let cells = try Cells(field: copy field, variableCount: n, using: &admission)
                let ring = cells.polynomials
                var guardLaw = try ring.constant(field.integer(1, using: &admission), using: &admission)
                for denominator in law.parameterTransport.denominators {
                    try admission.consumeWork(1)
                    let value = try imported(denominator, into: ring, field: field, using: &admission)
                    guard try !ring.isZero(value, using: &admission) else { throw NativeExactRelationFailure.invalidDomain }
                    guardLaw = try ring.multiplying(guardLaw, value, using: &admission)
                }
                try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: ExactPolynomial<Field>.self))
                var homogeneous: [ExactPolynomial<Field>] = []; homogeneous.reserveCapacity(4)
                for equation in law.homogeneous {
                    try admission.consumeWork(1)
                    homogeneous.append(try ring.multiplying(imported(equation, into: ring, field: field, using: &admission),
                        guardLaw, using: &admission))
                }
                let first = chart.selectedLocal.axes[0].intervals
                let secondCount = n == 2 ? chart.selectedLocal.axes[1].intervalCount : 1
                for i in first.indices {
                    for j in 0..<secondCount {
                        try admission.consumeWork(1)
                        guard result.count < maximumMaps else { throw NativeExactRelationFailure.domain(.chartLimit) }
                        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: n,
                            of: ExactRealRootInterval<Field.Value>.self))
                        var selected: [ExactRealRootInterval<Field.Value>] = []; selected.reserveCapacity(n)
                        for axis in 0..<n {
                            let interval = axis == 0 ? first[i] : chart.selectedLocal.axes[1].intervals[j]
                            guard case .finite(let lower) = interval.lower, case .finite(let upper) = interval.upper else {
                                throw NativeExactRelationFailure.unsupportedCoverage
                            }
                            selected.append(try roots.domain(lower: .finite(field.importingBase(lower, using: &admission)),
                                upper: .finite(field.importingBase(upper, using: &admission)),
                                includesLower: interval.includesLower, includesUpper: interval.includesUpper, using: &admission))
                        }
                        let source = try cells.bind(polynomials: homogeneous, domains: selected, using: &admission)
                        let map = try domain.map(from: source, using: &admission)
                        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalIssuedSelectedMap.self))
                        result.append(.init(chartIndex: chartIndex, map: map))
                    }
                }
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                of: OriginalIssuedMapPreparation<Source, Selection>.self))
            let resultOwner = OriginalIssuedMapPreparation(original: copy cover, field: copy field, maps: result, coefficientTransfer: coefficientTransfer)
            try admission.checkpoint(); return resultOwner
        } catch { throw .preserving(error) }
    }
    private func imported<A: ExactScalarAdmission & ~Copyable>(_ polynomial: ExactPolynomial<Base>,
        into ring: ExactPolynomialDomain<Field>, field: borrowing Field, using admission: inout A
    ) throws -> ExactPolynomial<Field> {
        try admission.admitDepth(value: polynomial.depth.value, coefficient: polynomial.depth.coefficient)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: polynomial.terms.count,
            of: ExactPolynomialTerm<Field.Value>.self))
        var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(polynomial.terms.count)
        for term in polynomial.terms {
            try admission.consumeWork(1)
            terms.append(.init(powers: term.powers, coefficient: try field.importingBase(term.coefficient, using: &admission)))
        }
        return try ring.polynomial(terms: terms, using: &admission)
    }
}
