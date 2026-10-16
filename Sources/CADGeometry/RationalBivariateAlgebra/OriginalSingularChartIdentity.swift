/// Source-bound identity for a transient, deterministically issued ramified chart.
package struct OriginalSingularChartIdentity: Hashable, Sendable {
    package let original: ExactBivariatePolynomial
    package let station: ExactBivariateSystemRoot
    package let germOrdinal: Int
    package let spanOrdinal: Int
    package let localDomain: SurfaceParameterBox
    package let sourceDomain: SurfaceParameterBox
    package let start: OriginalSingularFieldEndpoint
    package let end: OriginalSingularFieldEndpoint
    package let originalAnchor: ExactRationalCoefficient?
    package let halfBranchSector: Int
    package let halfBranchOrdinal: Int
    package let halfBranchSide: Int

    package init<B: ExactScalarAdmission & ~Copyable>(resolution: OriginalSingularResolution,
        germOrdinal: Int, clip: OriginalSingularRegularChartClip, spanOrdinal: Int, usage: inout B) throws {
        guard germOrdinal >= 0, germOrdinal < resolution.germs.count,
            spanOrdinal >= 0, spanOrdinal < clip.spans.count,
            resolution.germs[germOrdinal].strictTransform.context === clip.chart.germ.strictTransform.context else {
            throw rationalAlgebraFailure("Original ramified identity has a different issued leaf or clipping sector.")
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        let span = clip.spans[spanOrdinal]
        original = resolution.original; station = resolution.originalStation
        self.germOrdinal = germOrdinal; self.spanOrdinal = spanOrdinal
        localDomain = clip.chart.localDomain; sourceDomain = clip.sourceDomain
        start = clip.stations[span.lowerStation].endpoint; end = clip.stations[span.upperStation].endpoint
        originalAnchor = nil; halfBranchSector = -1; halfBranchOrdinal = -1; halfBranchSide = -1
    }
    package init<B: ExactScalarAdmission & ~Copyable>(resolution: OriginalSingularResolution, germOrdinal: Int,
        attachment: OriginalSingularHalfBranchAttachment, chart: OriginalSingularRegularChart,
        sourceDomain: SurfaceParameterBox, usage: inout B) throws {
        guard germOrdinal == attachment.chartIndex, germOrdinal >= 0, germOrdinal < resolution.germs.count,
            resolution.germs[germOrdinal].strictTransform.context === chart.germ.strictTransform.context else {
            throw rationalAlgebraFailure("Original half-chart identity has a different issued leaf.")
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        original = resolution.original; station = resolution.originalStation
        self.germOrdinal = germOrdinal; spanOrdinal = -1
        localDomain = chart.localDomain; self.sourceDomain = sourceDomain
        start = .authored(.zero); end = .authored(.zero)
        originalAnchor = attachment.originalFreeWitness
        halfBranchSector = attachment.halfBranch.sectorIndex
        halfBranchOrdinal = attachment.halfBranch.branchOrdinal
        halfBranchSide = attachment.halfBranch.side == .lowerStation ? 0 : 1
    }
    package static func == (a: Self, b: Self) -> Bool {
        guard a.original == b.original, a.germOrdinal == b.germOrdinal, a.spanOrdinal == b.spanOrdinal,
            a.localDomain == b.localDomain, a.sourceDomain == b.sourceDomain,
            a.originalAnchor == b.originalAnchor, a.halfBranchSector == b.halfBranchSector,
            a.halfBranchOrdinal == b.halfBranchOrdinal, a.halfBranchSide == b.halfBranchSide,
            same(a.start, b.start), same(a.end, b.end), a.station.equations == b.station.equations,
            a.station.projectionRoot.polynomial == b.station.projectionRoot.polynomial,
            same(.algebraic(a.station.projectionRoot), .algebraic(b.station.projectionRoot)) else { return false }
        let x = a.station.fiberRoot, y = b.station.fiberRoot
        guard x.lower == y.lower, x.upper == y.upper, x.excludesLower == y.excludesLower,
            x.excludesUpper == y.excludesUpper, x.isolationDepth == y.isolationDepth,
            a.station.fiber.coefficients.count == b.station.fiber.coefficients.count else { return false }
        for (index, first) in a.station.fiber.coefficients {
            guard let second = b.station.fiber.coefficients[index],
                first.numerator == second.numerator, first.denominator == second.denominator else { return false }
        }
        return true
    }
    private static func same(_ a: OriginalSingularFieldEndpoint, _ b: OriginalSingularFieldEndpoint) -> Bool {
        switch (a, b) {
        case (.authored(let x), .authored(let y)): return x == y
        case (.algebraic(let x), .algebraic(let y)):
            return x.isolation.lower == y.isolation.lower && x.isolation.upper == y.isolation.upper
                && x.isolation.excludesLower == y.isolation.excludesLower && x.isolation.excludesUpper == y.isolation.excludesUpper
                && x.isolation.depth == y.isolation.depth
        default: return false
        }
    }
    private static func same(_ a: ExactMonotoneGraphEndpoint, _ b: ExactMonotoneGraphEndpoint) -> Bool { a.identityEquals(b) }
    package func hash(into hasher: inout Hasher) {
        hasher.combine(germOrdinal); hasher.combine(spanOrdinal); hasher.combine(localDomain); hasher.combine(sourceDomain)
        ExactMonotoneGraphEndpoint.algebraic(station.projectionRoot).hashIdentity(into: &hasher)
        hasher.combine(halfBranchSector); hasher.combine(halfBranchOrdinal); hasher.combine(halfBranchSide)
        if let originalAnchor {
            hasher.combine(originalAnchor.canonicalSign); hasher.combine(originalAnchor.canonicalNumeratorWords)
            hasher.combine(originalAnchor.canonicalDenominatorWords)
        }
        func hash(_ endpoint: OriginalSingularFieldEndpoint) {
            hasher.combine(endpoint.lower.canonicalSign); hasher.combine(endpoint.lower.canonicalNumeratorWords)
            hasher.combine(endpoint.lower.canonicalDenominatorWords); hasher.combine(endpoint.upper.canonicalSign)
            hasher.combine(endpoint.upper.canonicalNumeratorWords); hasher.combine(endpoint.upper.canonicalDenominatorWords)
            hasher.combine(endpoint.depth)
        }
        hash(start); hash(end)
    }
}
