#if SOURCE_ISSUED_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
@testable import DI
#elseif ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Proves finite affine chart coverage; no source preparation or solving is repeated.
public struct DefaultOriginalIssuedDomainBinder<Source: Sendable, Selection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalIssuedDomainBinding
    where Field.Source == Field.Value {
    public init() {}
    public func bind<A: ExactScalarAdmission & ~Copyable>(
        laws: borrowing [OriginalRationalChartReceipt<Source, Selection, Field>],
        request: borrowing OriginalParameterSelection<Source, Field>,
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalIssuedDomainCover<Source, Selection, Field> {
        do {
            try admission.checkpoint()
            guard laws.count <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            let transporter = DefaultOriginalParameterTransporter<Source, Field>()
            let field = request.frame.scalarField
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: laws.count,
                of: OriginalParameterTransport<Source, Field>.self))
            var maps: [OriginalParameterTransport<Source, Field>] = []; maps.reserveCapacity(laws.count)
            for lawIndex in laws.indices {
                let law = laws[lawIndex]
                try admission.consumeWork(1); try law.admitProof(using: &admission)
                guard request.frame.source.owns(law.chart), law.support.count == request.arity,
                    law.polynomials.variableCount == request.arity, (1...2).contains(request.arity),
                    law.parameterTransport.numerators.count == request.arity,
                    law.parameterTransport.denominators.count == request.arity else {
                    throw OriginalDomainIdentityFailure.foreignOwner
                }
                let n = request.arity
                try admission.retainStorage(bytes: exactScalarPayloadBytes(count: n, of: Int.self))
                try admission.retainStorage(bytes: exactScalarPayloadBytes(count: n, of: Field.Value.self))
                try admission.retainStorage(bytes: exactScalarPayloadBytes(count: n, of: Field.Value.self))
                try admission.retainStorage(bytes: exactScalarPayloadBytes(count: n,
                    of: [ExactParameterInterval<Field.Value>].self))
                var permutation: [Int] = [], gains: [Field.Value] = [], offsets: [Field.Value] = []
                var support: [[ExactParameterInterval<Field.Value>]] = []
                permutation.reserveCapacity(n); gains.reserveCapacity(n); offsets.reserveCapacity(n); support.reserveCapacity(n)
                for axis in 0..<n {
                    try admission.consumeWork(1)
                    let ring = law.polynomials
                    let divided = try ring.divided(law.parameterTransport.numerators[axis],
                        by: law.parameterTransport.denominators[axis], using: &admission)
                    // FIXME(INCOMPLETE_IMPLEMENTATION): This finite composition port
                    // consumes issuer-certified affine correspondence. Non-affine
                    // source transport needs exact domain pullback before publication.
                    guard try ring.isZero(divided.remainder, using: &admission) else {
                        throw OriginalDomainIdentityFailure.unsupportedSourceProof
                    }
                    var selectedAxis: Int?, gain = try field.integer(0, using: &admission), offset = gain
                    for term in divided.quotient.terms {
                        try admission.consumeWork(1)
                        var active: Int?
                        for index in term.powers.indices {
                            try admission.consumeWork(1)
                            if term.powers[index] == 0 { continue }
                            guard term.powers[index] == 1, active == nil else {
                                throw OriginalDomainIdentityFailure.unsupportedSourceProof
                            }
                            active = index
                        }
                        let coefficient = try field.importing(term.coefficient, using: &admission)
                        if let active {
                            guard selectedAxis == nil else { throw OriginalDomainIdentityFailure.unsupportedSourceProof }
                            selectedAxis = active; gain = coefficient
                        } else { offset = coefficient }
                    }
                    guard let selectedAxis else { throw OriginalDomainIdentityFailure.singularTransport }
                    permutation.append(selectedAxis); gains.append(gain); offsets.append(offset)
                    let interval = law.support[axis]
                    try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                        of: ExactParameterInterval<Field.Value>.self))
                    support.append([try .checked(field: field,
                        lower: .finite(field.importing(interval.lower, using: &admission)),
                        upper: .finite(field.importing(interval.upper, using: &admission)),
                        depth: law.proofDepth ?? .init(value: 0, coefficient: 0), using: &admission)])
                }
                try admission.retainStorage(bytes: exactScalarPayloadBytes(count: n, of: OriginalCoordinateSemantics.self))
                let frame = try transporter.frame(source: law.source, field: field, support: support,
                    semantics: Array(request.frame.coordinateSemantics), limits: limits, using: &admission)
                maps.append(try transporter.affine(from: frame.fullSelection(limits: limits, using: &admission),
                    to: request.frame, permutation: permutation, gains: gains, offsets: offsets,
                    limits: limits, using: &admission))
            }
            let cover = try DefaultOriginalDomainCoverIssuer<Source, Field>().issue(request: request,
                charts: maps, limits: limits, using: &admission)
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: cover.charts.count,
                of: OriginalIssuedDomainChart<Source, Field>.self))
            var charts: [OriginalIssuedDomainChart<Source, Field>] = []; charts.reserveCapacity(cover.charts.count)
            var nextTemplate = 0
            for chart in cover.charts {
                var originalIndex: Int?
                // Coverage preserves template order and every local frame was
                // issued separately above. Advance once instead of rescanning.
                while nextTemplate < maps.count {
                    try admission.consumeWork(1)
                    let index = nextTemplate; nextTemplate += 1
                    if chart.transport.local.sharesFrame(with: maps[index].local) { originalIndex = index; break }
                }
                guard let originalIndex else { throw OriginalDomainIdentityFailure.invalidDomain }
                let inverse = try transporter.inverse(chart.transport, limits: limits, using: &admission)
                let selected = try transporter.restrict(inverse, to: chart.selectedImage, limits: limits, using: &admission)
                charts.append(.init(lawIndex: originalIndex, selectedLocal: selected.image, transport: chart.transport))
            }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                of: OriginalIssuedDomainCover<Source, Selection, Field>.self))
            let result = OriginalIssuedDomainCover(laws: copy laws, coverage: cover, charts: charts)
            try admission.checkpoint(); return result
        } catch { throw .init(preserving: error) }
    }
}
