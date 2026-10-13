import CADCore

/// Retains the actual cardinal plane's authored UV basis unchanged.
public struct OriginalCertifiedConeConeTargetSnapshotProvider: OriginalSourceSnapshotting {
    public let tolerance: ModelingTolerance
    public init(tolerance: ModelingTolerance) { self.tolerance = tolerance }
    public static func supports(_ surface: Surface3D) -> Bool {
        guard case .plane(let p) = surface else { return false }
        return p.origin == .origin && p.normal == .unitX && p.uDirection == .unitZ
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Surface3D,
        limits: OriginalSourceIssuanceLimits, using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<Surface3D> {
        let input = copy input
        do {
            try a.checkpoint(); try a.consumeWork(1)
            guard Self.supports(input) else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            guard limits.remainingSourceDepth >= 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            try input.validate(tolerance: tolerance)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Surface3D.self))
            try a.checkpoint(); return .init(original: input, sourceDepth: 0)
        } catch { throw .init(preserving: error) }
    }
}
