/// Retains the actual source/host bindings, complete graph coverage and every lifted incident.
public struct OriginalImplicitCurveRelations<T: Sendable,F: Sendable,D: Sendable>: OriginalImplicitCurveRelationReading {
    public typealias Cover = OriginalCompleteCurveGraphDomainCover<OriginalImplicitCurveSnapshot,
        OriginalImplicitCurveGraphEvidence,OriginalFiniteImplicitCurveGraphCoverage>
    public typealias Geometry = OriginalIssuedGeometricRelations<OriginalImplicitCurveSnapshot,
        OriginalImplicitCurveGraphEvidence,Cover,T,F,D>
    public let issuedGeometry: Geometry
    public let geometry: any OriginalIssuedGeometricRelationReading
    public var original: OriginalImplicitCurveSnapshot { issuedGeometry.original.first.source.original }
    public var finiteCoverage: OriginalFiniteImplicitCurveGraphCoverage { issuedGeometry.original.first.coverage.family.coverage }
    /// The first stored cell only; use finiteCoverage for the whole authored family.
    public var firstEvidence: OriginalImplicitCurveGraphEvidence { firstReduction.original.evidence }
    /// The sealed source coverage is nonempty and ordered by stored cell ordinal.
    public var firstReduction: OriginalImplicitCurveGraphReduction { finiteCoverage.reductions[0] }
    @available(*, deprecated, renamed: "firstEvidence", message: "This is only the first stored cell; finiteCoverage owns the whole family.")
    public var evidence: OriginalImplicitCurveGraphEvidence { firstEvidence }
    @available(*, deprecated, renamed: "firstReduction", message: "This is only the first stored cell; finiteCoverage owns the whole family.")
    public var reduction: OriginalImplicitCurveGraphReduction { firstReduction }
    public var isEmpty: Bool { geometry.isEmpty }
    public var hasPositiveDimensionalSolutions: Bool { geometry.hasPositiveDimensionalSolutions }
    public var hasPositiveDimensionalImage: Bool { geometry.hasPositiveDimensionalImage }

    init(issuedGeometry: Geometry, geometry: any OriginalIssuedGeometricRelationReading) {
        self.issuedGeometry = issuedGeometry; self.geometry = geometry
    }
}
