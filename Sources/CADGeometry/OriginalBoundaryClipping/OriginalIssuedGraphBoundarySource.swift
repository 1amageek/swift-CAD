import CADCore

/// Complete graph receipt and checked literal support for one selected surface role.
public struct OriginalIssuedGraphBoundarySource<S: Sendable, E: Sendable, C: Sendable, T: Sendable, F: Sendable, D: Sendable>: Sendable {
    public enum Side: Sendable { case first, second }
    public let raw: OriginalIssuedGraphRelations<S, E, C, T, F, D>
    public let side: Side
    public let surface: Surface3D

    private init(raw: OriginalIssuedGraphRelations<S, E, C, T, F, D>, side: Side, surface: Surface3D) {
        self.raw = raw
        self.side = side
        self.surface = surface
    }

    public static func firstSurface<A: ExactScalarAdmission & ~Copyable>(
        _ raw: OriginalIssuedGraphRelations<S, E, C, T, F, D>, binding: OriginalFaceSurfaceBinding<S>,
        limits: OriginalDomainIdentityLimits, using a: inout A
    ) throws(NativeExactRelationFailure) -> Self {
        do {
            try raw.admitProof(limits: limits, using: &a)
            guard raw.kind == .surfaceSurface, raw.first.parameterCount == 2 else { throw NativeExactRelationFailure.invalidDomain }
            guard binding.source.owner === raw.first.source.owner else { throw OriginalDomainIdentityFailure.foreignOwner }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
            let result = Self(raw: raw, side: .first, surface: binding.surface)
            try a.checkpoint()
            return result
        } catch { throw .preserving(error) }
    }

    public static func secondSurface<A: ExactScalarAdmission & ~Copyable>(
        _ raw: OriginalIssuedGraphRelations<S, E, C, T, F, D>, binding: OriginalFaceSurfaceBinding<T>,
        limits: OriginalDomainIdentityLimits, using a: inout A
    ) throws(NativeExactRelationFailure) -> Self {
        do {
            try raw.admitProof(limits: limits, using: &a)
            guard raw.second.parameterCount == 2 else { throw NativeExactRelationFailure.invalidDomain }
            guard binding.source.owner === raw.second.source.owner else { throw OriginalDomainIdentityFailure.foreignOwner }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
            let result = Self(raw: raw, side: .second, surface: binding.surface)
            try a.checkpoint()
            return result
        } catch { throw .preserving(error) }
    }

    package func matches<A: ExactScalarAdmission & ~Copyable>(_ stored: Surface3D,
        limits: OriginalDomainIdentityLimits, using a: inout A) throws -> Bool {
        try raw.admitProof(limits: limits, using: &a)
        switch (surface, stored) {
        case (.bSpline, .bSpline): break
        case (.procedural(.originalCoons), .procedural(.originalCoons(let coons))):
            func admit(_ span: OriginalCurveRootSpan3D) throws {
                try a.consumeWork(1)
                guard limits.source.remainingSourceDepth > 0,
                    span.remainingSourceDepth < limits.source.remainingSourceDepth else { throw OriginalDomainIdentityFailure.sourceDepthLimit }
            }
            try admit(coons.vMinimumBoundary)
            try admit(coons.vMaximumBoundary)
            try admit(coons.uMinimumBoundary)
            try admit(coons.uMaximumBoundary)
        default:
            try a.checkpoint()
            return false
        }
        try GeometryStructuralComparisonWork.charge(surface: surface, using: &a)
        try GeometryStructuralComparisonWork.charge(surface: stored, using: &a)
        let equal = surface == stored
        try a.checkpoint()
        return equal
    }
}
