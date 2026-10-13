import CADCore

/// Retains the declared plane frame or the unit coaxial cylinder unchanged.
public struct OriginalCertifiedCoaxialTargetSnapshotProvider: OriginalSourceSnapshotting {
    public let tolerance: ModelingTolerance
    public init(tolerance: ModelingTolerance) { self.tolerance = tolerance }

    public static func isPlane(_ surface: Surface3D) -> Bool {
        guard case .plane(let plane) = surface else { return false }
        return plane.origin == .origin && plane.normal == .unitY && plane.uDirection == .unitX
    }

    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Surface3D,
        limits: OriginalSourceIssuanceLimits, using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<Surface3D> {
        let input = copy input
        do {
            try a.checkpoint(); try a.consumeWork(1)
            guard limits.remainingSourceDepth >= 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            let cylinder = Surface3D.analytic(.cylinder(origin: .origin, axis: .unitZ, radius: 1))
            guard Self.isPlane(input) || input == cylinder else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            try input.validate(tolerance: tolerance)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Surface3D.self))
            try a.checkpoint(); return .init(original: input, sourceDepth: 0)
        } catch { throw .init(preserving: error) }
    }
}
