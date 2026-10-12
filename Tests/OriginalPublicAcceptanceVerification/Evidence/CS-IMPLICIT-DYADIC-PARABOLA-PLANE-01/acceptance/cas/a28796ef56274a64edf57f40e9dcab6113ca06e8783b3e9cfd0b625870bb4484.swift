/// Retains the actual source/host bindings, complete graph coverage and every lifted incident.
public struct OriginalImplicitCurveRelations<T: Sendable,F: Sendable,D: Sendable>: OriginalImplicitCurveRelationReading {
    public typealias Cover = OriginalCompleteCurveGraphDomainCover<OriginalImplicitCurveSnapshot,
        OriginalImplicitCurveGraphEvidence,OriginalImplicitCurveGraphReduction>
    public typealias Geometry = OriginalIssuedGeometricRelations<OriginalImplicitCurveSnapshot,
        OriginalImplicitCurveGraphEvidence,Cover,T,F,D>
    public let issuedGeometry: Geometry
    public let geometry: any OriginalIssuedGeometricRelationReading
    public var original: OriginalImplicitCurveSnapshot { issuedGeometry.original.first.source.original }
    public var evidence: OriginalImplicitCurveGraphEvidence { reduction.original.evidence }
    public var reduction: OriginalImplicitCurveGraphReduction { issuedGeometry.original.first.coverage.family.coverage }
    public var isEmpty: Bool { geometry.isEmpty }
    public var hasPositiveDimensionalSolutions: Bool { geometry.hasPositiveDimensionalSolutions }
    public var hasPositiveDimensionalImage: Bool { geometry.hasPositiveDimensionalImage }

    init(issuedGeometry: Geometry, geometry: any OriginalIssuedGeometricRelationReading) {
        self.issuedGeometry = issuedGeometry; self.geometry = geometry
    }
}
