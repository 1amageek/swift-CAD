/// Conservative identity of a field chart issued by one immutable original resolution.
struct SurfaceSilhouetteFieldChartIdentity: Hashable, Sendable {
    let owner: OriginalSingularFieldContext
    let localDomain: SurfaceParameterBox
    let sourceDomain: SurfaceParameterBox
    let germOrdinal: Int
    let sectorOrdinal: Int
    let branchOrdinal: Int
    let upperSide: Bool
    let anchor: ExactRationalCoefficient

    static func == (a: Self, b: Self) -> Bool {
        a.owner === b.owner && a.localDomain == b.localDomain && a.sourceDomain == b.sourceDomain
            && a.germOrdinal == b.germOrdinal && a.sectorOrdinal == b.sectorOrdinal
            && a.branchOrdinal == b.branchOrdinal && a.upperSide == b.upperSide && a.anchor == b.anchor
    }
    func hash(into hasher: inout Hasher) {
        // Unrelated immutable owners may collide; equality never identifies them.
        hasher.combine(localDomain); hasher.combine(sourceDomain); hasher.combine(germOrdinal)
        hasher.combine(sectorOrdinal); hasher.combine(branchOrdinal); hasher.combine(upperSide)
        hasher.combine(anchor.canonicalSign); hasher.combine(anchor.canonicalNumeratorWords)
        hasher.combine(anchor.canonicalDenominatorWords)
    }
}
