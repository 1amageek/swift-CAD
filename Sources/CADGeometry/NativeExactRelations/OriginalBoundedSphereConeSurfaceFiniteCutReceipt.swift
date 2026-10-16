import CADCore

// FIXME(INCOMPLETE_IMPLEMENTATION): Public bounded SSI currently composes
// a leading excluded region, one upper-azimuth boundary candidate and the
// trailing selected arc. Other guard arrangements fail explicitly until their
// complete source cover and boundary incidences are supported and verified.
public struct OriginalBoundedSphereConeSurfaceFiniteCutReceipt: Sendable {
    typealias Certifier = OriginalBoundedSphereConeFiniteArcCertifier
    typealias CellProof = Certifier.CellProof
    typealias Exclusion = OriginalBoundedSphereConeFiniteArcExclusionReceipt
    public typealias Root = OriginalBoundedSphereConeBoundaryRootReceipt
    public typealias Source = OriginalBoundedSphereConeSurfaceSnapshot

    enum Resolution {
        case empty(OriginalBoundedSphereConeSurfaceFiniteCutReceipt)
        case selected(OriginalBoundedSphereConeSurfaceFiniteArcReceipt)
        case cut(OriginalBoundedSphereConeSurfaceFiniteCutReceipt)
    }
    private struct Pending {
        let u: ScalarInterval
        let depth: Int
        let coefficientDepth: Int
    }

    public let source: OriginalSourceBinding<Source>
    public let firstBox: SurfaceParameterBox
    public let secondBox: SurfaceParameterBox
    public let boundaryRoot: Root?
    public let proofDepth: ExactScalarDepth
    private let preparation: OriginalGeometryPreparationReceipt
    private let selected: [CellProof]
    private let excluded: [Exclusion]
    private let candidate: CellProof?
    public var isEmpty: Bool { boundaryRoot == nil }
    public var imageDimension: Int? { isEmpty ? nil : 1 }
    public var branch: Int? { candidate?.branch }

    private init(source: OriginalSourceBinding<Source>, firstBox: SurfaceParameterBox,
        secondBox: SurfaceParameterBox, selected: consuming [CellProof],
        excluded: consuming [Exclusion], candidate: CellProof?, root: Root?,
        preparation: OriginalGeometryPreparationReceipt, proofDepth: ExactScalarDepth) {
        self.source = source; self.firstBox = firstBox; self.secondBox = secondBox
        self.selected = selected; self.excluded = excluded; self.candidate = candidate
        boundaryRoot = root; self.preparation = preparation; self.proofDepth = proofDepth
    }

    /// Every classified leaf is retained; an unfinished leaf cannot be published.
    static func resolve(source: OriginalSourceBinding<Source>, firstBox: SurfaceParameterBox,
        secondBox: SurfaceParameterBox, tolerance: ModelingTolerance,
        limits: OriginalSourceIssuanceLimits, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> Resolution {
        try execution.checkpoint(); try source.require(limits)
        try execution.admitSourceDepth(source.sourceDepth)
        try tolerance.validate()
        guard maximumSpanCount > 0, maximumSubdivisionDepth >= 0, maximumAlgebraicDepth >= 0 else {
            throw OriginalSourceIssuanceFailure.invalidSource
        }
        let original = source.original
        let sphere = original.sphereIsFirst ? firstBox : secondBox
        let cone = original.sphereIsFirst ? secondBox : firstBox
        let cellLimit = min(maximumSpanCount, execution.effectiveLimits.maximumSpans)
        let depthLimit = min(maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth)
        let coefficientLimit = min(maximumAlgebraicDepth, execution.effectiveLimits.maximumCoefficientDepth)
        // The existing whole-selected certifier begins at coefficient depth two.
        guard coefficientLimit >= 2 else { throw ExactScalarFailure.resourceLimit(.coefficientDepth) }
        let prepared = try execution.withPreparationScope { execution in
            try execution.withProofScope(maximum: .init(value: maximumAlgebraicDepth,
                coefficient: coefficientLimit)) { execution in
                let certifier = try Certifier(source: source, sphere: sphere, cone: cone, using: &execution)
                var coefficients = try certifier.makeCoefficientContinuation(using: &execution)
                var pending: [Pending] = [], selected: [CellProof] = [], excluded: [Exclusion] = []
                var candidates: [CellProof] = []
                var pendingCapacity = 0, selectedCapacity = 0, excludedCapacity = 0, candidateCapacity = 0
                try append(Pending(u: cone.u, depth: 0, coefficientDepth: 2), to: &pending,
                    capacity: &pendingCapacity, using: &execution)
                var cursor = cone.u.lower, visited = 0, phase = 0
                while let cell = pending.popLast() {
                    try execution.checkpoint(); try execution.consumeWork(1)
                    guard visited < cellLimit else { throw OriginalDomainIdentityFailure.chartLimit }
                    visited += 1
                    try execution.visitCertificationCell(depth: cell.depth)
                    guard cell.u.lower == cursor else { throw ExactScalarFailure.invalidEvidence }
                    let childCone = SurfaceParameterBox(u: cell.u, v: cone.v)
                    let first = original.sphereIsFirst ? sphere : childCone
                    let second = original.sphereIsFirst ? childCone : sphere
                    let refinementDepth = try certifier.refinementDepth(overClosedRawU: cell.u,
                        minimum: cell.coefficientDepth, continuation: coefficients, using: &execution)
                    switch try Exclusion.decide(source: source, firstBox: first, secondBox: second,
                        refinementDepth: refinementDepth, continuation: &coefficients,
                        limits: limits, using: &execution) {
                    case .wholeCellExcluded(let proof):
                        guard phase == 0 else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                        try append(proof, to: &excluded, capacity: &excludedCapacity, using: &execution)
                        cursor = cell.u.upper
                    case .selected(let proof):
                        phase = 2
                        try append(proof, to: &selected, capacity: &selectedCapacity, using: &execution)
                        cursor = cell.u.upper
                    case .boundaryCandidate(let proof) where phase != 2 && !excluded.isEmpty
                        && proof.kind == .boundaryCandidate(guardReason: .sphereAzimuthUpper):
                        phase = 1
                        try append(proof, to: &candidates, capacity: &candidateCapacity, using: &execution)
                        cursor = cell.u.upper
                    case .boundaryCandidate, .unresolved:
                        if cell.u.lower == cell.u.upper || cell.depth == depthLimit {
                            let next = refinementDepth.addingReportingOverflow(1)
                            guard !next.overflow else { throw ExactScalarFailure.countOverflow }
                            guard next.partialValue <= coefficientLimit else { throw OriginalDomainIdentityFailure.incompleteCoverage }
                            try append(Pending(u: cell.u, depth: cell.depth, coefficientDepth: next.partialValue),
                                to: &pending, capacity: &pendingCapacity, using: &execution)
                        } else {
                            let middle = cell.u.midpoint
                            guard middle.isFinite, middle > cell.u.lower, middle < cell.u.upper else {
                                throw OriginalDomainIdentityFailure.incompleteCoverage
                            }
                            let next = cell.depth.addingReportingOverflow(1)
                            guard !next.overflow else { throw ExactScalarFailure.countOverflow }
                            // Stack order preserves ascending coverage without sorting or copies.
                            try append(Pending(u: .init(lower: middle, upper: cell.u.upper), depth: next.partialValue,
                                coefficientDepth: cell.coefficientDepth), to: &pending,
                                capacity: &pendingCapacity, using: &execution)
                            try append(Pending(u: .init(lower: cell.u.lower, upper: middle), depth: next.partialValue,
                                coefficientDepth: cell.coefficientDepth), to: &pending,
                                capacity: &pendingCapacity, using: &execution)
                        }
                    }
                }
                guard cursor == cone.u.upper else { throw OriginalDomainIdentityFailure.incompleteCoverage }
                if candidates.isEmpty {
                    if selected.isEmpty {
                        guard !excluded.isEmpty else { throw OriginalDomainIdentityFailure.incompleteCoverage }
                        return (selected, excluded, Optional<CellProof>.none, Optional<Root>.none)
                    }
                    guard excluded.isEmpty else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                    return (selected, excluded, Optional<CellProof>.none, Optional<Root>.none)
                }
                guard !excluded.isEmpty, !selected.isEmpty else { throw OriginalDomainIdentityFailure.incompleteCoverage }
                let candidate = try CellProof.unionBoundaryCandidates(candidates, limits: limits, using: &execution)
                let provider = try OriginalBoundedSphereConeBoundaryJetProvider(source: source, limits: limits, using: &execution)
                var session = try provider.makeSession(limits: limits, using: &execution)
                let boundarySphere = SurfaceParameterBox(u: try .init(lower: sphere.u.upper, upper: sphere.u.upper), v: sphere.v)
                let candidateCone = original.sphereIsFirst ? candidate.secondBox : candidate.firstBox
                let first = original.sphereIsFirst ? boundarySphere : candidateCone
                let second = original.sphereIsFirst ? candidateCone : boundarySphere
                let box = SurfaceIntersectionParameterBox(firstU: first.u, firstV: first.v,
                    secondU: second.u, secondV: second.v)
                let outcome = try Root.issue(provider: provider, session: &session, candidate: candidate, parameterBox: box,
                    boundaryCoordinate: original.sphereIsFirst ? .firstU : .secondU,
                    boundaryStation: sphere.u.upper, coefficientRefinementDepth: 3,
                    tolerance: tolerance, limits: limits, maximumSpanCount: cellLimit,
                    maximumSubdivisionDepth: depthLimit, maximumAlgebraicDepth: maximumAlgebraicDepth,
                    using: &execution)
                guard case .unique(let root) = outcome else { throw OriginalDomainIdentityFailure.incompleteCoverage }
                guard root.source.owner === source.owner, root.requestedBox == box else {
                    throw OriginalSourceIssuanceFailure.foreignBinding
                }
                let u = try root.coordinate(original.sphereIsFirst ? .secondU : .firstU,
                    limits: limits, using: &execution).enclosure(limits: limits, using: &execution)
                guard u.lower > candidate.coneU.lowerBound, u.upper < candidate.coneU.upperBound else {
                    throw OriginalDomainIdentityFailure.incompleteCoverage
                }
                let q = ExactRationalScalarDomain()
                for proof in selected {
                    try execution.consumeWork(1)
                    guard proof.source.owner === source.owner, proof.branch == candidate.branch,
                        try q.compare(proof.coneCycle, candidate.coneCycle, using: &execution) == .equal,
                        try q.compare(proof.sphereCycle, candidate.sphereCycle, using: &execution) == .equal else {
                        throw OriginalSourceIssuanceFailure.foreignBinding
                    }
                }
                return (selected, excluded, Optional(candidate), Optional(root))
            }
        }
        let preparation = try OriginalGeometryPreparationReceipt(tolerance: tolerance,
            depth: prepared.depth, using: &execution)
        if prepared.result.2 == nil, !prepared.result.0.isEmpty {
            return .selected(try OriginalBoundedSphereConeSurfaceFiniteArcReceipt.assemble(
                selected: prepared.result.0, preparation: preparation, limits: limits, using: &execution))
        }
        try execution.retainStorage(count: 1, stride: MemoryLayout<Self>.stride)
        let result = Self(source: source, firstBox: firstBox, secondBox: secondBox,
            selected: prepared.result.0, excluded: prepared.result.1,
            candidate: prepared.result.2, root: prepared.result.3,
            preparation: preparation, proofDepth: preparation.depth.scalar)
        try execution.checkpoint()
        return result.isEmpty ? .empty(result) : .cut(result)
    }

    public func admitProof(limits: OriginalSourceIssuanceLimits,
        using execution: inout OriginalQueryExecution) throws {
        try withRead(limits: limits, using: &execution) { execution in
            try execution.checkpoint()
        }
    }

    /// An authored binary64 label is exact input, never a rounded root endpoint.
    func position(coneU rawU: Double, branch: Int,
        coneCycle: OriginalParameterCycle, sphereCycle: OriginalParameterCycle,
        limits: OriginalSourceIssuanceLimits, using execution: inout OriginalQueryExecution)
        throws -> OriginalBoundedSphereConeSurfaceFiniteArcPosition {
        try withRead(limits: limits, using: &execution) { execution in
            guard rawU.isFinite else { throw OriginalDomainIdentityFailure.invalidDomain }
            guard let candidate, branch == candidate.branch else {
                throw OriginalDomainIdentityFailure.outsideSupport
            }
            let q = ExactRationalScalarDomain()
            guard try q.compare(coneCycle.original, candidate.coneCycle, using: &execution) == .equal,
                try q.compare(sphereCycle.original, candidate.sphereCycle, using: &execution) == .equal else {
                throw OriginalDomainIdentityFailure.outsideSupport
            }
            for proof in selected {
                try execution.checkpoint(); try execution.consumeWork(1)
                if proof.coneU.contains(rawU) {
                    let arc = try OriginalBoundedSphereConeSurfaceFiniteArcReceipt.assemble(
                        selected: proof, preparation: preparation, limits: limits, using: &execution)
                    let u = try source.original.field.binary64(exactly: rawU, using: &execution)
                    return try arc.position(coneU: u, using: &execution)
                }
            }
            guard candidate.coneU.contains(rawU) else { throw OriginalDomainIdentityFailure.outsideSupport }
            let s = source.original
            let sphere = s.sphereIsFirst ? firstBox : secondBox
            let cone = s.sphereIsFirst ? secondBox : firstBox
            let pointCone = SurfaceParameterBox(u: try .init(lower: rawU, upper: rawU), v: cone.v)
            let first = s.sphereIsFirst ? sphere : pointCone
            let second = s.sphereIsFirst ? pointCone : sphere
            let certifier = try Certifier(source: source, sphere: sphere, cone: pointCone, using: &execution)
            var continuation = try certifier.makeCoefficientContinuation(using: &execution)
            var depth = 2
            while true {
                try execution.checkpoint()
                switch try Exclusion.decide(source: source, firstBox: first, secondBox: second,
                    refinementDepth: depth, continuation: &continuation, limits: limits, using: &execution) {
                case .wholeCellExcluded:
                    throw OriginalDomainIdentityFailure.outsideSupport
                case .selected(let proof):
                    guard proof.branch == branch else { throw OriginalSourceIssuanceFailure.foreignBinding }
                    let arc = try OriginalBoundedSphereConeSurfaceFiniteArcReceipt.assemble(
                        selected: proof, preparation: preparation, limits: limits, using: &execution)
                    let u = try source.original.field.binary64(exactly: rawU, using: &execution)
                    return try arc.position(coneU: u, using: &execution)
                case .boundaryCandidate, .unresolved:
                    let next = depth.addingReportingOverflow(1)
                    guard !next.overflow else { throw ExactScalarFailure.countOverflow }
                    guard next.partialValue <= execution.effectiveLimits.maximumCoefficientDepth else {
                        throw OriginalDomainIdentityFailure.incompleteCoverage
                    }
                    depth = next.partialValue
                }
            }
        }
    }

    private func withRead<Result>(limits: OriginalSourceIssuanceLimits,
        using execution: inout OriginalQueryExecution,
        _ body: (inout OriginalQueryExecution) throws -> Result) throws -> Result {
        // Check caller ceilings before contribution reattachment can allocate;
        // the inner admissions still enforce effective contribution ceilings.
        try execution.checkpoint(); try source.require(limits)
        let retained = preparation.depth
        try execution.admitSourceDepth(max(source.sourceDepth, retained.sourceDepth))
        let sourceProof = source.original.proofDepth
        try execution.admitDepth(value: max(retained.scalar.value, max(proofDepth.value, sourceProof.value)),
            coefficient: max(retained.scalar.coefficient, max(proofDepth.coefficient, sourceProof.coefficient)))
        try execution.admitGeometricDepth(retained.geometricDepth)
        try execution.admitTransportDepth(retained.transportDepth)
        return try preparation.withContributionScopes(using: &execution) { execution in
            try execution.checkpoint(); try source.require(limits)
            try execution.admitSourceDepth(source.sourceDepth)
            try preparation.admit(tolerance: preparation.tolerance, using: &execution)
            try execution.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
            let result = try body(&execution)
            try execution.checkpoint()
            return result
        }
    }

    private static func append<T>(_ value: consuming T, to array: inout [T], capacity: inout Int,
        using execution: inout OriginalQueryExecution) throws {
        if array.count == capacity {
            let next = capacity.multipliedReportingOverflow(by: 2)
            guard !next.overflow else { throw ExactScalarFailure.countOverflow }
            let newCapacity = max(1, next.partialValue)
            try execution.retainStorage(count: newCapacity, stride: MemoryLayout<T>.stride)
            array.reserveCapacity(newCapacity); capacity = newCapacity
        }
        array.append(value)
    }
}
