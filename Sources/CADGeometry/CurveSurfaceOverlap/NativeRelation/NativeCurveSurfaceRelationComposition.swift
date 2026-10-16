import CADCore

/// One original refinement makes chart ownership and cross-chart closure exact.
package struct NativeCurveSurfaceRelationComposition: Sendable {
    package struct Binding: Sendable {
        let equationStart: Int
        let boundStart: Int
        let minorStart: Int
        let jacobian: ExactIntersectionJacobian
        let finalUpper: [Bool]
        let excludedByUpperBoundary: Bool
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
    package let originalLawUnits: [ExactRationalCoefficient]
    package let finiteCoordinateWitnesses: [Int]
    package let necessaryCoordinateEquations: [ExactIntersectionPolynomial]

    package init<B: ExactScalarAdmission & ~Copyable>(charts: [NativeCurveSurfacePointChart],
        nativeDomains: [OriginalRationalParameterDomain], requestedDomains: [OriginalRationalParameterDomain], effectiveDomains: [OriginalRationalParameterDomain]?,
        maximumCandidateCount: Int, maximumDepth: Int, tolerance: ModelingTolerance,
        usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        try RationalAlgebraStorage.retain(charts.count, of: Binding.self, usage: &usage)
        var bindings: [Binding] = []; bindings.reserveCapacity(charts.count)
        var lawCount = 0
        for chart in charts {
            let jacobian = try ExactIntersectionJacobian.prepare(equations: chart.system.equations,
                variableCount: 3, usage: &usage)
            try RationalAlgebraStorage.retain(3, of: Bool.self, usage: &usage)
            var final: [Bool] = []; final.reserveCapacity(3)
            for axis in 0..<3 {
                try intersectionAlgebraStep(&usage)
                final.append(chart.nativeDomains[axis].upper == nativeDomains[axis].upper)
            }
            var excluded = effectiveDomains == nil
            if let selected = effectiveDomains {
                for axis in 0..<3 {
                    try intersectionAlgebraStep(&usage)
                    if !final[axis] && chart.nativeDomains[axis].upper == selected[axis].lower { excluded = true }
                }
            }
            bindings.append(.init(equationStart: lawCount, boundStart: try rationalAlgebraCount(lawCount, 5),
                minorStart: try rationalAlgebraCount(lawCount, 11), jacobian: jacobian, finalUpper: final, excludedByUpperBoundary: excluded))
            if !excluded { lawCount = try rationalAlgebraCount(lawCount, rationalAlgebraCount(11, jacobian.minors.count)) }
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
            if binding.excludedByUpperBoundary { try intersectionAlgebraStep(&usage); continue }
            let system = chart.system
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
                let domain = chart.nativeDomains[axis]
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
        try RationalAlgebraStorage.retain(lawCount, of: ExactRationalCoefficient.self, usage: &usage)
        var units: [ExactRationalCoefficient] = []; units.reserveCapacity(lawCount)
        var originalToIssued: [Int] = []; originalToIssued.reserveCapacity(lawCount)
        var issued: [ExactIntersectionPolynomial] = []; issued.reserveCapacity(lawCount)
        for polynomial in polynomials {
            let leading = try polynomial.leading(usage: &usage)
            let normalized: ExactIntersectionPolynomial
            if let leading {
                normalized = try polynomial.scaled(by: .one.divided(by: leading.coefficient, usage: &usage), usage: &usage)
            } else { normalized = polynomial }
            units.append(leading?.coefficient ?? .one)
            var equal: Int?
            for (ordinal, retained) in issued.enumerated() {
                try intersectionAlgebraStep(&usage)
                if try normalized.matches(retained, usage: &usage) { equal = ordinal; break }
            }
            if let equal { originalToIssued.append(equal) }
            else { originalToIssued.append(issued.count); issued.append(normalized) }
        }
        for index in instructions.indices {
            try intersectionAlgebraStep(&usage)
            if case .sign(let original, let sign) = instructions[index] {
                let originalSign: OriginalPolynomialPredicate.Sign
                if units[original].isNegative {
                    switch sign { case .positive: originalSign = .negative; case .negative: originalSign = .positive; case .zero: originalSign = .zero }
                } else { originalSign = sign }
                instructions[index] = .sign(polynomial: originalToIssued[original], originalSign)
            }
        }
        let program = try OriginalPolynomialPredicate(polynomialCount: issued.count, instructions: instructions, usage: &usage)
        let witnessCapacity = try rationalAlgebraCount(charts.count, 3, multiply: true)
        try RationalAlgebraStorage.retain(witnessCapacity, of: Int.self, usage: &usage)
        try RationalAlgebraStorage.retain(charts.count, of: Int.self, usage: &usage)
        try RationalAlgebraStorage.retain(3, of: ExactIntersectionPolynomial.self, usage: &usage)
        var witnesses: [Int] = []; witnesses.reserveCapacity(witnessCapacity)
        var factors: [Int] = []; factors.reserveCapacity(charts.count)
        var necessary: [ExactIntersectionPolynomial] = []; necessary.reserveCapacity(3)
        var finite = effectiveDomains != nil
        for axis in 0..<3 {
            guard finite else { break }
            factors.removeAll(keepingCapacity: true)
            for binding in bindings {
                try intersectionAlgebraStep(&usage)
                if binding.excludedByUpperBoundary { continue }
                var witness: Int?
                for equation in 0..<3 {
                    let ordinal = binding.equationStart + equation
                    let original = polynomials[ordinal]
                    if original.isConstant { continue }
                    var univariate = true
                    for (power, _) in try original.orderedTerms(usage: &usage) {
                        for other in 0..<3 where other != axis {
                            try intersectionAlgebraStep(&usage)
                            if try power.exponent(at: other) != 0 { univariate = false }
                        }
                    }
                    if univariate { witness = ordinal; break }
                }
                guard let witness else { finite = false; break }
                witnesses.append(witness)
                let factor = originalToIssued[witness]
                var retained = false
                for existing in factors { try intersectionAlgebraStep(&usage); if existing == factor { retained = true; break } }
                if !retained { factors.append(factor) }
            }
            guard finite, !factors.isEmpty else { finite = false; break }
            var product = try ExactIntersectionPolynomial.constant(variableCount: 3, value: .one, usage: &usage)
            for factor in factors { product = try product.multiplied(by: issued[factor], usage: &usage) }
            necessary.append(product)
        }
        if !finite { witnesses.removeAll(keepingCapacity: true); necessary.removeAll(keepingCapacity: true) }
        // Every selected tuple zeros these original necessary constraints. All three
        // independent coordinate witnesses prove finiteness before prefix pruning.
        let ambient = try OriginalRationalIntersectionCells.prepare(equations: necessary, variableCount: 3,
            exactDomains: effectiveDomains ?? requestedDomains, partitionPolynomials: issued,
            thomEncoding: true, pruneExcludedPrefixes: finite, maximumDepth: maximumDepth, usage: &usage)
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
            func originalSign(_ original: Int) -> ExactAlgebraicRealRoot.Sign {
                let sign = signs[offset + originalToIssued[original]]
                guard units[original].isNegative else { return sign }
                switch sign { case .positive: return .negative; case .negative: return .positive; case .zero: return .zero }
            }
            for (ordinal, binding) in bindings.enumerated() {
                try intersectionAlgebraStep(&usage)
                if binding.excludedByUpperBoundary { continue }
                var included = true
                for axis in 0..<3 {
                    try intersectionAlgebraStep(&usage)
                    if originalSign(binding.equationStart + axis) != .zero { included = false }
                    let lower = originalSign(binding.boundStart + axis * 2)
                    let upper = originalSign(binding.boundStart + axis * 2 + 1)
                    if lower == .negative || (binding.finalUpper[axis] ? upper == .positive : upper != .negative) { included = false }
                }
                for guardIndex in 0..<2 {
                    if originalSign(binding.equationStart + 3 + guardIndex) == .zero { included = false }
                }
                if included {
                    guard owners[index] == -1 else { throw rationalAlgebraFailure("Two original charts own one common parameter cell.") }
                    owners[index] = ordinal
                    for (minorOrdinal, minor) in binding.jacobian.minors.enumerated() {
                        try intersectionAlgebraStep(&usage)
                        if originalSign(binding.minorStart + minorOrdinal) != .zero {
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
        chartOwners = owners; ranks = originalRanks; sourceBindings = bindings; originalLawOrdinals = originalToIssued; originalLawUnits = units
        finiteCoordinateWitnesses = witnesses; necessaryCoordinateEquations = necessary
        try CurrentTaskCancellationChecker().checkCancellation()
    }
}
