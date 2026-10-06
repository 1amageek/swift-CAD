import CADCore

/// Original Jacobian rank is constant on every issued real solution cell; incidence is not implied.
package struct OriginalRationalIntersectionStrata: Sendable {
    package struct Stratum: Sendable {
        package let cellIndex: Int
        package let originalJacobianRank: Int
        package let isolatedRankSigns: [ExactAlgebraicRealRoot.Sign]?
        package let rankAdmissionDepth: Int?
        package let rankCoefficientAdmissionDepth: Int?

        package init(cellIndex: Int, originalJacobianRank: Int,
            isolatedRankSigns: [ExactAlgebraicRealRoot.Sign]? = nil,
            rankAdmissionDepth: Int? = nil, rankCoefficientAdmissionDepth: Int? = nil) {
            self.cellIndex = cellIndex; self.originalJacobianRank = originalJacobianRank
            self.isolatedRankSigns = isolatedRankSigns; self.rankAdmissionDepth = rankAdmissionDepth
            self.rankCoefficientAdmissionDepth = rankCoefficientAdmissionDepth
        }
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
        isolatedOnly: Bool = false,
        pruneExcludedPrefixes: Bool = false, maximumDepth: Int, usage: inout B) throws -> Self {
        try prepareOriginal(equations: originalRankEquations ?? ideal.originalEquations, ideal: ideal, variableCount: ideal.variableCount,
            exactDomains: exactDomains, nonzeroPolynomials: nonzeroPolynomials,
            thomEncoding: thomEncoding, pruneExcludedPrefixes: pruneExcludedPrefixes,
            isolatedOnly: isolatedOnly, maximumDepth: maximumDepth, usage: &usage)
    }

    private static func prepareOriginal<B: RationalAlgebraAdmitting>(equations: [ExactIntersectionPolynomial],
        ideal: ExactIntersectionIdeal?, variableCount: Int, exactDomains: [OriginalRationalParameterDomain],
        nonzeroPolynomials: [ExactIntersectionPolynomial], thomEncoding: Bool, pruneExcludedPrefixes: Bool,
        isolatedOnly: Bool = false, maximumDepth: Int, usage: inout B) throws -> Self {
        if isolatedOnly {
            return try prepareIsolated(equations: equations, ideal: ideal, variableCount: variableCount,
                exactDomains: exactDomains, nonzeroPolynomials: nonzeroPolynomials,
                thomEncoding: thomEncoding, pruneExcludedPrefixes: pruneExcludedPrefixes,
                maximumDepth: maximumDepth, usage: &usage)
        }
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

    private static func prepareIsolated<B: RationalAlgebraAdmitting>(equations: [ExactIntersectionPolynomial],
        ideal: ExactIntersectionIdeal?, variableCount: Int, exactDomains: [OriginalRationalParameterDomain],
        nonzeroPolynomials: [ExactIntersectionPolynomial], thomEncoding: Bool, pruneExcludedPrefixes: Bool,
        maximumDepth: Int, usage: inout B) throws -> Self {
        for domain in exactDomains {
            try intersectionAlgebraStep(&usage)
            guard domain.lower != nil, domain.upper != nil else {
                throw rationalAlgebraFailure("Isolated native rank evaluation requires finite closed original domains.")
            }
        }
        let partition = try OriginalRationalIntersectionCells.prepare(equations: ideal?.reducedBasis ?? equations,
            variableCount: variableCount, exactDomains: exactDomains, nonzeroPolynomials: nonzeroPolynomials,
            thomEncoding: thomEncoding, pruneExcludedPrefixes: pruneExcludedPrefixes,
            maximumDepth: maximumDepth, usage: &usage)
        for index in partition.solutionCells {
            try intersectionAlgebraStep(&usage)
            guard partition.cells[index].dimension == 0 else {
                throw KernelError(phase: .geometry, code: .nonDiscreteIntersection, tolerance: nil,
                    message: "The original requested native product contains a positive-dimensional intersection.")
            }
        }
        let jacobian = try ExactIntersectionJacobian.prepare(equations: equations, variableCount: variableCount, usage: &usage)
        try RationalAlgebraStorage.retain(jacobian.minors.count, of: ExactIntersectionPolynomial.self, usage: &usage)
        var witnesses: [ExactIntersectionPolynomial] = []; witnesses.reserveCapacity(jacobian.minors.count)
        for minor in jacobian.minors {
            try intersectionAlgebraStep(&usage)
            witnesses.append(try ideal.map { try ExactIntersectionGroebnerBasis.reduced(minor.polynomial,
                by: $0.reducedBasis, usage: &usage) } ?? minor.polynomial)
        }
        try RationalAlgebraStorage.retain(partition.solutionCells.count, of: Stratum.self, usage: &usage)
        var strata: [Stratum] = []; strata.reserveCapacity(partition.solutionCells.count)
        for index in partition.solutionCells {
            let cell = partition.cells[index]
            var admission = OriginalSourceScalarAdmission(base: usage, maximumDepth: maximumDepth,
                maximumCoefficientDepth: partition.maximumCoefficientDepth,
                originalParameterDepth: cell.context.depth, originalCoefficientDepth: cell.context.coefficientDepth,
                inheritedParameterDepth: cell.admissionDepth, inheritedCoefficientDepth: cell.coefficientAdmissionDepth,
                parameterDepth: cell.admissionDepth, coefficientDepth: cell.coefficientAdmissionDepth)
            defer { usage = admission.base }
            let availableDepth = try rationalAlgebraCount(cell.context.depth, maximumDepth - cell.admissionDepth)
            try RationalAlgebraStorage.retain(witnesses.count, of: ExactAlgebraicRealRoot.Sign.self, usage: &admission)
            var signs: [ExactAlgebraicRealRoot.Sign] = []; signs.reserveCapacity(witnesses.count)
            var rank = 0
            for (ordinal, polynomial) in witnesses.enumerated() {
                let sign = try OriginalIntersectionFieldEvaluation.evaluated(polynomial, context: cell.context,
                    coordinates: cell.coordinates, maximumDepth: availableDepth, usage: &admission)
                    .sign(maximumDepth: availableDepth, usage: &admission)
                signs.append(sign)
                if sign != .zero { rank = max(rank, jacobian.minors[ordinal].order) }
            }
            // A zero-dimensional cell is one exact tuple, so these original
            // indexed minor signs prove its rank without further partitioning.
            strata.append(.init(cellIndex: index, originalJacobianRank: rank, isolatedRankSigns: signs,
                rankAdmissionDepth: admission.parameterDepth,
                rankCoefficientAdmissionDepth: admission.coefficientDepth))
        }
        return Self(equationIdeal: ideal, jacobian: jacobian, partition: partition, strata: strata)
    }
}
