import CADCore

/// Issues the full branch's actual physical radial traversal as an auxiliary source.
struct OriginalCertifiedSphereConePhaseProvider: OriginalSourceSnapshotting {
    func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing CertifiedSphereConeIntersectionCurve,
        limits: OriginalSourceIssuanceLimits, using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalCertifiedSphereConePhase> {
        do {
            try a.checkpoint(); try a.consumeWork(1)
            guard limits.remainingSourceDepth >= 1 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            guard input.lowerAngle == 0, input.upperAngle == 2 * Double.pi else { throw OriginalSourceIssuanceFailure.invalidSource }
            switch input.componentKind {
            case .negativeFullBranch, .positiveFullBranch: break
            default: throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            let end = try ExactRationalScalarDomain().binary64(exactly: 2 * Double.pi, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalCertifiedSphereConePhase.self))
            let snapshot = OriginalCertifiedSphereConePhase(original: copy input, end: end)
            try a.checkpoint(); return .init(original: snapshot, sourceDepth: 1)
        } catch { throw .init(preserving: error) }
    }
}
