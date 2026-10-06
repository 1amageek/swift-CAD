import CADCore

/// One original refinement makes chart ownership and cross-chart closure exact.
package struct NativeCurveSurfaceRelationComposition: Sendable {
    package struct Binding: Sendable {
        let equationStart: Int
        let boundStart: Int
        let minorStart: Int
        let jacobian: ExactIntersectionJacobian
        let finalUpper: [Bool]
    }
    package let laws: [ExactIntersectionPolynomial]
    package let predicate: OriginalPolynomialPredicate
    package let partition: OriginalRationalIntersectionCells
    package let incidence: OriginalRationalIntersectionIncidence
    package let connected: OriginalRationalParameterComponents
    package let chartOwners: [Int]
    package let ranks: [Int]
    package let sourceBindings: [Binding]
    package let originalLawOrdinals: [Int]

    package init<B: RationalAlgebraAdmitting>(charts: [NativeCurveSurfacePointChart],
        nativeDomains: [OriginalRationalParameterDomain], effectiveDomains: [OriginalRationalParameterDomain]?,
        maximumCandidateCount: Int, maximumDepth: Int, tolerance: ModelingTolerance,
        usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        try RationalAlgebraStorage.retain(charts.count, of: Binding.self, usage: &usage)
        var bindings: [Binding] = []; bindings.reserveCapacity(charts.count)
        var lawCount = 0
        for chart in charts {
            let jacobian = try ExactIntersectionJacobian.prepare(equations: chart.decomposition.system.equations,
                variableCount: 3, usage: &usage)
            try RationalAlgebraStorage.retain(3, of: Bool.self, usage: &usage)
            var final: [Bool] = []; final.reserveCapacity(3)
            for axis in 0..<3 {
                try intersectionAlgebraStep(&usage)
                final.append(chart.decomposition.nativeDomains[axis].upper == nativeDomains[axis].upper)
            }
            bindings.append(.init(equationStart: lawCount, boundStart: try rationalAlgebraCount(lawCount, 5),
                minorStart: try rationalAlgebraCount(lawCount, 11), jacobian: jacobian, finalUpper: final))
            lawCount = try rationalAlgebraCount(lawCount, rationalAlgebraCount(11, jacobian.minors.count))
        }
        try RationalAlgebraStorage.retain(lawCount, of: ExactIntersectionPolynomial.self, usage: &usage)
        var polynomials: [ExactIntersectionPolynomial] = []; polynomials.reserveCapacity(lawCount)
        // Each chart uses 1 literal + 6 equality + 6 guard + 18 bound + 1 union instructions.
        let instructionCount = try rationalAlgebraCount(1, rationalAlgebraCount(charts.count, 32, multiply: true))
        try RationalAlgebraStorage.retain(instructionCount, of: OriginalPolynomialPredicate.Instruction.self, usage: &usage)
        var instructions: [OriginalPolynomialPredicate.Instruction] = []; instructions.reserveCapacity(instructionCount)
        instructions.append(.literal(false))
        for (ordinal, chart) in charts.enumerated() {
            let binding = bindings[ordinal]
            let system = chart.decomposition.system
            polynomials.append(contentsOf: system.equations); polynomials.append(contentsOf: system.denominatorGuards)
            instructions.append(.literal(effectiveDomains != nil))
            for axis in 0..<3 {
                instructions.append(.sign(polynomial: binding.equationStart + axis, .zero)); instructions.append(.and)
            }
            for axis in 0..<2 {
                instructions.append(.sign(polynomial: binding.equationStart + 3 + axis, .zero))
                instructions.append(.not); instructions.append(.and)
            }
            for axis in 0..<3 {
                let domain = chart.decomposition.nativeDomains[axis]
                guard let lower = domain.lower, let upper = domain.upper else {
                    throw rationalAlgebraFailure("Native chart composition requires every finite original bound.")
                }
                let coordinate = try ExactIntersectionPolynomial.coordinate(variableCount: 3, at: axis, usage: &usage)
                polynomials.append(try coordinate.subtracting(.constant(variableCount: 3, value: lower, usage: &usage), usage: &usage))
                polynomials.append(try coordinate.subtracting(.constant(variableCount: 3, value: upper, usage: &usage), usage: &usage))
                instructions.append(.sign(polynomial: binding.boundStart + axis * 2, .negative))
                instructions.append(.not); instructions.append(.and)
                instructions.append(.sign(polynomial: binding.boundStart + axis * 2 + 1,
                    binding.finalUpper[axis] ? .positive : .negative))
                if binding.finalUpper[axis] { instructions.append(.not) }
                instructions.append(.and)
            }
            for minor in binding.jacobian.minors { polynomials.append(minor.polynomial) }
            instructions.append(.or)
        }
        try RationalAlgebraStorage.retain(lawCount, of: Int.self, usage: &usage)
        try RationalAlgebraStorage.retain(lawCount, of: ExactIntersectionPolynomial.self, usage: &usage)
        var originalToIssued: [Int] = []; originalToIssued.reserveCapacity(lawCount)
        var issued: [ExactIntersectionPolynomial] = []; issued.reserveCapacity(lawCount)
        for polynomial in polynomials {
            var equal: Int?
            for (ordinal, retained) in issued.enumerated() {
                try intersectionAlgebraStep(&usage)
                if try polynomial.matches(retained, usage: &usage) { equal = ordinal; break }
            }
            if let equal { originalToIssued.append(equal) }
            else { originalToIssued.append(issued.count); issued.append(polynomial) }
        }
        for index in instructions.indices {
            try intersectionAlgebraStep(&usage)
            if case .sign(let original, let sign) = instructions[index] {
                instructions[index] = .sign(polynomial: originalToIssued[original], sign)
            }
        }
        let program = try OriginalPolynomialPredicate(polynomialCount: issued.count, instructions: instructions, usage: &usage)
        let ambient = try OriginalRationalIntersectionCells.prepare(equations: [], variableCount: 3,
            exactDomains: effectiveDomains ?? nativeDomains, partitionPolynomials: issued,
            thomEncoding: true, maximumDepth: maximumDepth, usage: &usage)
        let selected = try ambient.selecting(program.original, usage: &usage)
        guard selected.solutionCells.count <= maximumCandidateCount else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Native common-refinement cells exceed the cumulative result ceiling.")
        }
        try RationalAlgebraStorage.retain(selected.cells.count, of: Int.self, usage: &usage)
        try RationalAlgebraStorage.retain(selected.cells.count, of: Int.self, usage: &usage)
        var owners = Array(repeating: -1, count: selected.cells.count)
        var originalRanks = Array(repeating: 0, count: selected.cells.count)
        for index in selected.solutionCells {
            let signs = selected.cells[index].signs, offset = selected.partitionSignOffset
            for (ordinal, binding) in bindings.enumerated() {
                try intersectionAlgebraStep(&usage)
                var included = true
                for axis in 0..<3 {
                    try intersectionAlgebraStep(&usage)
                    if signs[offset + originalToIssued[binding.equationStart + axis]] != .zero { included = false }
                    let lower = signs[offset + originalToIssued[binding.boundStart + axis * 2]]
                    let upper = signs[offset + originalToIssued[binding.boundStart + axis * 2 + 1]]
                    if lower == .negative || (binding.finalUpper[axis] ? upper == .positive : upper != .negative) { included = false }
                }
                for guardIndex in 0..<2 {
                    if signs[offset + originalToIssued[binding.equationStart + 3 + guardIndex]] == .zero { included = false }
                }
                if included {
                    guard owners[index] == -1 else { throw rationalAlgebraFailure("Two original charts own one common parameter cell.") }
                    owners[index] = ordinal
                    for (minorOrdinal, minor) in binding.jacobian.minors.enumerated() {
                        try intersectionAlgebraStep(&usage)
                        if signs[offset + originalToIssued[binding.minorStart + minorOrdinal]] != .zero {
                            originalRanks[index] = max(originalRanks[index], minor.order)
                        }
                    }
                }
            }
            guard owners[index] >= 0 else { throw rationalAlgebraFailure("A selected common parameter cell lost its original chart owner.") }
        }
        let joins = try OriginalRationalIntersectionIncidence.prepare(partition: selected, maximumDepth: maximumDepth, usage: &usage)
        let components = try joins.connectedComponents(usage: &usage)
        guard components.components.count <= maximumCandidateCount else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Native composed components exceed the cumulative result ceiling.")
        }
        laws = issued; predicate = program; partition = selected; incidence = joins; connected = components
        chartOwners = owners; ranks = originalRanks; sourceBindings = bindings; originalLawOrdinals = originalToIssued
        try CurrentTaskCancellationChecker().checkCancellation()
    }
}
