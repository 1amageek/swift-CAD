import CADCore

/// Retains a genuine single decomposition or genuine whole original refinement.
package enum NativeSurfaceSurfaceCoverage: Sendable {
    case single(OriginalRationalIntersectionDecomposition)
    case common(NativeSurfaceSurfaceCommonCoverage)

    package var nativeDomains: [OriginalRationalParameterDomain] {
        switch self { case .single(let proof): return proof.nativeDomains; case .common(let proof): return proof.nativeDomains }
    }
    package var requestedDomains: [OriginalRationalParameterDomain] {
        switch self { case .single(let proof): return proof.requestedDomains; case .common(let proof): return proof.requestedDomains }
    }
    package var effectiveDomains: [OriginalRationalParameterDomain]? {
        switch self { case .single(let proof): return proof.effectiveDomains; case .common(let proof): return proof.effectiveDomains }
    }
    package var partition: OriginalRationalIntersectionCells? {
        switch self {
        case .single(let proof): if case .parameterCells(let strata, _, _) = proof.coverage { return strata.partition }; return nil
        case .common(let proof): return proof.partition
        }
    }
    package var incidence: OriginalRationalIntersectionIncidence? {
        switch self { case .single(let proof): if case .parameterCells(_, let joins, _) = proof.coverage { return joins }; return nil
        case .common(let proof): return proof.incidence }
    }
    package var connected: OriginalRationalParameterComponents? {
        switch self { case .single(let proof): if case .parameterCells(_, _, let groups) = proof.coverage { return groups }; return nil
        case .common(let proof): return proof.connected }
    }
    package func chartIndex(cellIndex: Int) -> Int {
        switch self { case .single: return 0; case .common(let proof): return proof.chartOwners[cellIndex] }
    }
    package func firstLaw(cellIndex: Int) -> OriginalRationalSurfacePolynomial {
        switch self { case .single(let proof): return proof.system.firstSurfaceSource
        case .common(let proof): return proof.charts[proof.chartOwners[cellIndex]].first }
    }
    package func rank(ordinal: Int, cellIndex: Int) throws -> Int {
        switch self {
        case .single(let proof): guard case .parameterCells(let strata, _, _) = proof.coverage,
            strata.strata[ordinal].cellIndex == cellIndex else { throw rationalAlgebraFailure("SSI coverage lost its original rank binding.") }
            return strata.strata[ordinal].originalJacobianRank
        case .common(let proof): return proof.ranks[cellIndex]
        }
    }
}
