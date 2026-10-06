import CADCore

/// Original Jacobian rank is constant on every issued real solution cell; incidence is not implied.
package struct OriginalRationalIntersectionStrata: Sendable {
    package struct Stratum: Sendable {
        package let cellIndex: Int
        package let originalJacobianRank: Int
    }
    package let jacobian: ExactIntersectionJacobian
    package let partition: OriginalRationalIntersectionCells
    package let strata: [Stratum]

    private init(jacobian: ExactIntersectionJacobian, partition: OriginalRationalIntersectionCells,
        strata: [Stratum]) {
        self.jacobian = jacobian; self.partition = partition; self.strata = strata
    }

    package static func prepare<B: RationalAlgebraAdmitting>(equations: [ExactIntersectionPolynomial],
        variableCount: Int, domains: [ScalarInterval?], maximumDepth: Int, usage: inout B) throws -> Self {
        let jacobian = try ExactIntersectionJacobian.prepare(equations: equations, variableCount: variableCount, usage: &usage)
        try RationalAlgebraStorage.retain(jacobian.minors.count, of: ExactIntersectionPolynomial.self, usage: &usage)
        var witnesses: [ExactIntersectionPolynomial] = []; witnesses.reserveCapacity(jacobian.minors.count)
        for minor in jacobian.minors { try intersectionAlgebraStep(&usage); witnesses.append(minor.polynomial) }
        let partition = try OriginalRationalIntersectionCells.prepare(equations: equations, variableCount: variableCount,
            domains: domains, partitionPolynomials: witnesses, maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(partition.solutionCells.count, of: Stratum.self, usage: &usage)
        var strata: [Stratum] = []; strata.reserveCapacity(partition.solutionCells.count)
        for index in partition.solutionCells {
            try intersectionAlgebraStep(&usage)
            let cell = partition.cells[index]
            guard cell.signs.count - partition.partitionSignOffset == jacobian.minors.count else {
                throw rationalAlgebraFailure("A rational stratum lost its indexed original rank witnesses.")
            }
            var rank = 0
            for (ordinal, minor) in jacobian.minors.enumerated() {
                try intersectionAlgebraStep(&usage)
                if cell.signs[partition.partitionSignOffset + ordinal] != .zero { rank = max(rank, minor.order) }
            }
            strata.append(Stratum(cellIndex: index, originalJacobianRank: rank))
        }
        return Self(jacobian: jacobian, partition: partition, strata: strata)
    }
}
