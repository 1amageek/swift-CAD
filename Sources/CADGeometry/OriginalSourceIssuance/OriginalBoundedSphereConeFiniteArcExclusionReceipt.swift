import CADCore

struct OriginalBoundedSphereConeFiniteArcExclusionReceipt: Sendable {
    enum Decision: Sendable {
        case selected(OriginalBoundedSphereConeFiniteArcCertifier.CellProof)
        case boundaryCandidate(OriginalBoundedSphereConeFiniteArcCertifier.CellProof)
        case wholeCellExcluded(OriginalBoundedSphereConeFiniteArcExclusionReceipt)
        case unresolved(reason: OriginalBoundedSphereConeFiniteArcCertifier.UnresolvedReason)
    }

    let source: OriginalSourceBinding<OriginalBoundedSphereConeSurfaceSnapshot>
    let firstBox: SurfaceParameterBox
    let secondBox: SurfaceParameterBox
    let proofDepth: ExactScalarDepth

    private init(source: OriginalSourceBinding<OriginalBoundedSphereConeSurfaceSnapshot>,
        firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox, proofDepth: ExactScalarDepth) {
        self.source = source; self.firstBox = firstBox; self.secondBox = secondBox
        self.proofDepth = proofDepth
    }

    /// The sole receipt factory computes the entire bound cell's decision itself.
    static func decide<A: ExactScalarAdmission & ~Copyable>(
        source: OriginalSourceBinding<OriginalBoundedSphereConeSurfaceSnapshot>,
        firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
        refinementDepth: Int, continuation: inout OriginalBoundedSphereConeFiniteArcCertifier.CoefficientContinuation,
        limits: OriginalSourceIssuanceLimits, using a: inout A) throws -> Decision {
        try a.withProofScope { a in
            try a.checkpoint(); try a.consumeWork(1)
            try source.require(limits)
            let snapshot = source.original
            try a.admitDepth(value: snapshot.proofDepth.value, coefficient: snapshot.proofDepth.coefficient)
            try snapshot.firstLaw.admitProof(limits: limits, using: &a)
            try snapshot.secondLaw.admitProof(limits: limits, using: &a)
            let certifier = try OriginalBoundedSphereConeFiniteArcCertifier(source: source,
                sphere: snapshot.sphereIsFirst ? firstBox : secondBox,
                cone: snapshot.sphereIsFirst ? secondBox : firstBox, using: &a)
            let result: Decision
            switch try certifier.decision(refinementDepth: refinementDepth,
                continuation: &continuation, using: &a) {
            case .selected(let proof):
                result = .selected(proof)
            case .boundaryCandidate(let proof):
                result = .boundaryCandidate(proof)
            case .wholeCellExcluded:
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
                result = .wholeCellExcluded(Self(source: source, firstBox: firstBox,
                    secondBox: secondBox, proofDepth: try a.depth))
            case .unresolved(let reason):
                result = .unresolved(reason: reason)
            }
            try a.checkpoint(); return result
        }
    }

    func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws {
        try a.checkpoint()
        try source.require(limits)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        try a.checkpoint()
    }

    /// Exact source ownership and ordered raw request equality, never proximity.
    func accepts<A: ExactScalarAdmission & ~Copyable>(
        source requested: OriginalSourceBinding<OriginalBoundedSphereConeSurfaceSnapshot>,
        firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
        limits: OriginalSourceIssuanceLimits, using a: inout A) throws -> Bool {
        try admitProof(limits: limits, using: &a)
        try requested.require(limits)
        try a.consumeWork(1)
        let accepted = source.owner === requested.owner
            && self.firstBox == firstBox && self.secondBox == secondBox
        try a.checkpoint(); return accepted
    }
}
