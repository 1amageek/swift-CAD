import CADCore

/// Seals the literal face support to the source that issued its position laws.
public struct OriginalFaceSurfaceBinding<Source: Sendable>: Sendable {
    public let source: OriginalSourceBinding<Source>
    public let surface: Surface3D

    private init(source: OriginalSourceBinding<Source>, surface: Surface3D) {
        self.source = source
        self.surface = surface
    }

    public static func coons<A: ExactScalarAdmission & ~Copyable>(
        _ source: OriginalSourceBinding<Source>, limits: OriginalSourceIssuanceLimits, using a: inout A
    ) throws(OriginalSourceIssuanceFailure) -> Self where Source == OriginalCoonsAtlasSnapshot {
        do {
            try a.checkpoint()
            try source.require(limits)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
            let result = Self(source: source, surface: .procedural(.originalCoons(source.original.original)))
            try a.checkpoint()
            return result
        } catch { throw .init(preserving: error) }
    }

    public static func native<A: ExactScalarAdmission & ~Copyable>(
        _ source: OriginalSourceBinding<Source>, limits: OriginalSourceIssuanceLimits, using a: inout A
    ) throws(OriginalSourceIssuanceFailure) -> Self where Source == BSplineSurface3D {
        do {
            try a.checkpoint()
            try source.require(limits)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
            let result = Self(source: source, surface: .bSpline(source.original))
            try a.checkpoint()
            return result
        } catch { throw .init(preserving: error) }
    }
}
