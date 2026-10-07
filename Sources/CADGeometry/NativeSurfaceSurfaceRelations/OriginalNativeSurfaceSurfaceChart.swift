import CADCore

/// Closed original source-chart provenance; canonical cell ownership is separate.
public struct OriginalNativeSurfaceSurfaceChart: Sendable {
    public let firstUSpanIndex: Int
    public let firstVSpanIndex: Int
    public let secondUSpanIndex: Int
    public let secondVSpanIndex: Int
    /// Closed original u1,v1,u2,v2 supports, including all incident join charts.
    public let domains: [OriginalRationalParameterDomain]
}

extension NativeSurfaceSurfaceCoverage {
    package var sourceChartCount: Int {
        switch self { case .single: return 1; case .common(let proof): return proof.charts.count }
    }
    package func sourceChart(at ordinal: Int) throws -> OriginalNativeSurfaceSurfaceChart {
        guard (0..<sourceChartCount).contains(ordinal) else {
            throw GeometryConversionError.invalidInput("Native SSI source chart is outside its coverage owner.")
        }
        switch self {
        case .single(let proof):
            guard let second = proof.system.secondSurfaceSource else { throw rationalAlgebraFailure("SSI chart lost its second source law.") }
            let first = proof.system.firstSurfaceSource
            return .init(firstUSpanIndex: first.uSpanIndex, firstVSpanIndex: first.vSpanIndex,
                secondUSpanIndex: second.uSpanIndex, secondVSpanIndex: second.vSpanIndex, domains: proof.nativeDomains)
        case .common(let proof):
            let chart = proof.charts[ordinal]
            return .init(firstUSpanIndex: chart.firstOwner.uSpanIndex, firstVSpanIndex: chart.firstOwner.vSpanIndex,
                secondUSpanIndex: chart.secondOwner.uSpanIndex, secondVSpanIndex: chart.secondOwner.vSpanIndex, domains: chart.nativeDomains)
        }
    }
}
