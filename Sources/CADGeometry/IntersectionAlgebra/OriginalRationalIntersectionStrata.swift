import CADCore

/// Original Jacobian rank is constant on every issued real solution cell; incidence is not implied.
package struct OriginalRationalIntersectionStrata: Sendable {
    package struct Stratum: Sendable {
        package let cellIndex: Int
        package let originalJacobianRank: Int
    }
    package let equationIdeal: ExactIntersectionIdeal?
    package let jacobian: ExactIntersectionJacobian
    package let partition: OriginalRationalIntersectionCells
    package let strata: [Stratum]

    private init(equationIdeal: ExactIntersectionIdeal? = nil, jacobian: ExactIntersectionJacobian, partition: OriginalRationalIntersectionCells,
        strata: [Stratum]) {
        self.equationIdeal = equationIdeal; self.jacobian = jacobian; self.partition = partition; self.strata = strata
    }

    package static func prepare<B: RationalAlgebraAdmitting>(equations: [ExactIntersectionPolynomial],
        variableCount: Int, domains: [ScalarInterval?], thomEncoding: Bool = false, pruneExcludedPrefixes: Bool = false, maximumDepth: Int, usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        try RationalAlgebraStorage.retain(domains.count, of: OriginalRationalParameterDomain.self, usage: &usage)
        var exact: [OriginalRationalParameterDomain] = []; exact.reserveCapacity(domains.count)
        for domain in domains { exact.append(try .init(domain, usage: &usage)) }
        return try prepare(equations: equations, variableCount: variableCount, exactDomains: exact,
            thomEncoding: thomEncoding, pruneExcludedPrefixes: pruneExcludedPrefixes, maximumDepth: maximumDepth, usage: &usage)
    }

    package static func prepare<B: RationalAlgebraAdmitting>(equations: [ExactIntersectionPolynomial],
        variableCount: Int, exactDomains: [OriginalRationalParameterDomain], nonzeroPolynomials: [ExactIntersectionPolynomial] = [],
        thomEncoding: Bool = false, pruneExcludedPrefixes: Bool = false, maximumDepth: Int, usage: inout B) throws -> Self {
        return try prepareOriginal(equations: equations, ideal: nil, variableCount: variableCount,
            exactDomains: exactDomains, nonzeroPolynomials: nonzeroPolynomials,
            thomEncoding: thomEncoding, pruneExcludedPrefixes: pruneExcludedPrefixes, maximumDepth: maximumDepth, usage: &usage)
    }

    package static func prepare<B: RationalAlgebraAdmitting>(ideal: ExactIntersectionIdeal,
        exactDomains: [OriginalRationalParameterDomain], nonzeroPolynomials: [ExactIntersectionPolynomial],
        thomEncoding: Bool = false, originalRankEquations: [ExactIntersectionPolynomial]? = nil,
        pruneExcludedPrefixes: Bool = false, maximumDepth: Int, usage: inout B) throws -> Self {
        try prepareOriginal(equations: originalRankEquations ?? ideal.originalEquations, ideal: ideal, variableCount: ideal.variableCount,
            exactDomains: exactDomains, nonzeroPolynomials: nonzeroPolynomials,
            thomEncoding: thomEncoding, pruneExcludedPrefixes: pruneExcludedPrefixes, maximumDepth: maximumDepth, usage: &usage)
    }

    private static func prepareOriginal<B: RationalAlgebraAdmitting>(equations: [ExactIntersectionPolynomial],
        ideal: ExactIntersectionIdeal?, variableCount: Int, exactDomains: [OriginalRationalParameterDomain],
        nonzeroPolynomials: [ExactIntersectionPolynomial], thomEncoding: Bool, pruneExcludedPrefixes: Bool, maximumDepth: Int, usage: inout B) throws -> Self {
        let jacobian = try ExactIntersectionJacobian.prepare(equations: equations, variableCount: variableCount, usage: &usage)
        try RationalAlgebraStorage.retain(jacobian.minors.count, of: ExactIntersectionPolynomial.self, usage: &usage)
        var witnesses: [ExactIntersectionPolynomial] = []; witnesses.reserveCapacity(jacobian.minors.count)
        for minor in jacobian.minors {
            try intersectionAlgebraStep(&usage)
            witnesses.append(try ideal.map { try ExactIntersectionGroebnerBasis.reduced(minor.polynomial,
                by: $0.reducedBasis, usage: &usage) } ?? minor.polynomial)
        }
        let partition = try OriginalRationalIntersectionCells.prepare(equations: ideal?.reducedBasis ?? equations, variableCount: variableCount,
            exactDomains: exactDomains, partitionPolynomials: witnesses, nonzeroPolynomials: nonzeroPolynomials, thomEncoding: thomEncoding, pruneExcludedPrefixes: pruneExcludedPrefixes, maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(partition.solutionCells.count, of: Stratum.self, usage: &usage)
        var strata: [Stratum] = []; strata.reserveCapacity(partition.solutionCells.count)
        for index in partition.solutionCells {
            try intersectionAlgebraStep(&usage)
            let cell = partition.cells[index]
            guard cell.signs.count >= partition.partitionSignOffset + jacobian.minors.count else {
                throw rationalAlgebraFailure("A rational stratum lost its indexed original rank witnesses.")
            }
            var rank = 0
            for (ordinal, minor) in jacobian.minors.enumerated() {
                try intersectionAlgebraStep(&usage)
                if cell.signs[partition.partitionSignOffset + ordinal] != .zero { rank = max(rank, minor.order) }
            }
            strata.append(Stratum(cellIndex: index, originalJacobianRank: rank))
        }
        return Self(equationIdeal: ideal, jacobian: jacobian, partition: partition, strata: strata)
    }
}
