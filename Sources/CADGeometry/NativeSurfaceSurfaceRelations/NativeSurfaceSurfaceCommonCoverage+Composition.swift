import CADCore

/// One original refinement makes chart ownership and cross-chart closure exact.
extension NativeSurfaceSurfaceCommonCoverage {
    package struct Binding: Sendable {
        let equationStart: Int
        let boundStart: Int
        let minorStart: Int
        let jacobian: ExactIntersectionJacobian
        let guardedEquations: OriginalGuardedIntersectionEquations
        let equationIdeal: ExactIntersectionIdeal
        let sourceZeroSet: NativeSurfaceSourceZeroSetProof?
        let sourceCornerZeroSet: NativeSurfaceSourceCornerZeroSetProof?
        let cornerStart: Int
        let guardedOriginalRankWitnesses: OriginalGuardedIntersectionEquations
        let guardedRankWitnesses: OriginalGuardedIntersectionEquations
        let finalUpper: [Bool]
        let excludedByUpperBoundary: Bool
    }
    package static func prepare<B: ExactScalarAdmission & ~Copyable>(charts: [NativeSurfaceSurfaceSourceChart],
        nativeDomains: [OriginalRationalParameterDomain], requestedDomains: [OriginalRationalParameterDomain], effectiveDomains: [OriginalRationalParameterDomain]?,
        maximumComponentCount: Int, maximumDepth: Int, tolerance: ModelingTolerance,
        usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        try RationalAlgebraStorage.retain(charts.count, of: Binding.self, usage: &usage)
        var bindings: [Binding] = []; bindings.reserveCapacity(charts.count)
        var lawCount = 0
        for chart in charts {
            let guarded = try OriginalGuardedIntersectionEquations.prepare(equations: chart.system.equations,
                denominatorGuards: chart.system.denominatorGuards, variableCount: 4, usage: &usage)
            guard guarded.normalizedEquations.count == 3 else {
                throw rationalAlgebraFailure("Common SSI guarded laws lost their original three equation ordinals.")
            }
            let sourceZeroSet = try NativeSurfaceSourceZeroSetProof.prepare(chart: chart, usage: &usage)
            let sourceCornerZeroSet: NativeSurfaceSourceCornerZeroSetProof?
            if sourceZeroSet == nil { sourceCornerZeroSet = try NativeSurfaceSourceCornerZeroSetProof.prepare(chart: chart, usage: &usage) }
            else { sourceCornerZeroSet = nil }
            let equationCount = try rationalAlgebraCount(guarded.normalizedEquations.count,
                rationalAlgebraCount(sourceZeroSet?.consequences.count ?? 0, sourceCornerZeroSet?.consequences.count ?? 0))
            try RationalAlgebraStorage.retain(equationCount, of: ExactIntersectionPolynomial.self, usage: &usage)
            var chartEquations: [ExactIntersectionPolynomial] = []; chartEquations.reserveCapacity(equationCount)
            try usage.consumeWork(guarded.normalizedEquations.count)
            chartEquations.append(contentsOf: guarded.normalizedEquations)
            if let sourceZeroSet {
                try usage.consumeWork(sourceZeroSet.consequences.count)
                chartEquations.append(contentsOf: sourceZeroSet.consequences)
            }
            if let sourceCornerZeroSet {
                try usage.consumeWork(sourceCornerZeroSet.consequences.count)
                chartEquations.append(contentsOf: sourceCornerZeroSet.consequences)
            }
            let ideal = try ExactIntersectionIdeal.prepare(equations: chartEquations, variableCount: 4, usage: &usage)
            let jacobian = try ExactIntersectionJacobian.prepare(equations: chart.system.equations,
                variableCount: 4, usage: &usage)
            try RationalAlgebraStorage.retain(jacobian.minors.count, of: ExactIntersectionPolynomial.self, usage: &usage)
            var originalRankWitnesses: [ExactIntersectionPolynomial] = []; originalRankWitnesses.reserveCapacity(jacobian.minors.count)
            for minor in jacobian.minors {
                try intersectionAlgebraStep(&usage)
                originalRankWitnesses.append(minor.polynomial)
            }
            // Preserve guard divisibility before ideal reduction changes the
            // representative. Only zero/nonzero equivalence is used for rank.
            let guardedOriginalRanks = try OriginalGuardedIntersectionEquations.prepare(equations: originalRankWitnesses,
                denominatorGuards: chart.system.denominatorGuards, variableCount: 4, usage: &usage)
            guard guardedOriginalRanks.normalizedEquations.count == jacobian.minors.count else {
                throw rationalAlgebraFailure("Common SSI original guarded rank laws lost their indexed minor orders.")
            }
            try RationalAlgebraStorage.retain(jacobian.minors.count, of: ExactIntersectionPolynomial.self, usage: &usage)
            var rankWitnesses: [ExactIntersectionPolynomial] = []; rankWitnesses.reserveCapacity(jacobian.minors.count)
            for witness in guardedOriginalRanks.normalizedEquations {
                rankWitnesses.append(try ExactIntersectionGroebnerBasis.reduced(witness,
                    by: ideal.reducedBasis, usage: &usage))
            }
            let guardedRanks = try OriginalGuardedIntersectionEquations.prepare(equations: rankWitnesses,
                denominatorGuards: chart.system.denominatorGuards, variableCount: 4, usage: &usage)
            guard guardedRanks.normalizedEquations.count == jacobian.minors.count else {
                throw rationalAlgebraFailure("Common SSI rank laws lost their original indexed minor orders.")
            }
            try RationalAlgebraStorage.retain(4, of: Bool.self, usage: &usage)
            var final: [Bool] = []; final.reserveCapacity(4)
            for axis in 0..<4 {
                try intersectionAlgebraStep(&usage)
                final.append(chart.nativeDomains[axis].upper == nativeDomains[axis].upper)
            }
            var excluded = effectiveDomains == nil
            if let selected = effectiveDomains {
                for axis in 0..<4 {
                    try intersectionAlgebraStep(&usage)
                    if !final[axis] && chart.nativeDomains[axis].upper == selected[axis].lower { excluded = true }
                }
            }
            bindings.append(.init(equationStart: lawCount, boundStart: try rationalAlgebraCount(lawCount, 5),
                minorStart: try rationalAlgebraCount(lawCount, 13), jacobian: jacobian, guardedEquations: guarded, equationIdeal: ideal,
                sourceZeroSet: sourceZeroSet, sourceCornerZeroSet: sourceCornerZeroSet,
                cornerStart: try rationalAlgebraCount(lawCount, rationalAlgebraCount(13, jacobian.minors.count)),
                guardedOriginalRankWitnesses: guardedOriginalRanks, guardedRankWitnesses: guardedRanks, finalUpper: final, excludedByUpperBoundary: excluded))
            if !excluded { lawCount = try rationalAlgebraCount(lawCount,
                rationalAlgebraCount(13, rationalAlgebraCount(jacobian.minors.count, sourceCornerZeroSet?.consequences.count ?? 0))) }
        }
        try RationalAlgebraStorage.retain(lawCount, of: ExactIntersectionPolynomial.self, usage: &usage)
        var polynomials: [ExactIntersectionPolynomial] = []; polynomials.reserveCapacity(lawCount)
        // A bounded corner equation contributes two zero conjuncts instead of one.
        let instructionCount = try rationalAlgebraCount(1, rationalAlgebraCount(charts.count, 40, multiply: true))
        try RationalAlgebraStorage.retain(instructionCount, of: OriginalPolynomialPredicate.Instruction.self, usage: &usage)
        var instructions: [OriginalPolynomialPredicate.Instruction] = []; instructions.reserveCapacity(instructionCount)
        instructions.append(.literal(false))
        for (ordinal, chart) in charts.enumerated() {
            let binding = bindings[ordinal]
            if binding.excludedByUpperBoundary { try intersectionAlgebraStep(&usage); continue }
            let system = chart.system
            polynomials.append(contentsOf: binding.guardedEquations.normalizedEquations); polynomials.append(contentsOf: system.denominatorGuards)
            instructions.append(.literal(effectiveDomains != nil))
            for axis in 0..<3 {
                if let corner = binding.sourceCornerZeroSet, corner.equationIndex == axis {
                    for factor in corner.consequences.indices {
                        try usage.consumeWork(2)
                        instructions.append(.sign(polynomial: binding.cornerStart + factor, .zero)); instructions.append(.and)
                    }
                } else {
                    instructions.append(.sign(polynomial: binding.equationStart + axis, .zero)); instructions.append(.and)
                }
            }
            for axis in 0..<2 {
                instructions.append(.sign(polynomial: binding.equationStart + 3 + axis, .zero))
                instructions.append(.not); instructions.append(.and)
            }
            for axis in 0..<4 {
                let domain = chart.nativeDomains[axis]
                guard let lower = domain.lower, let upper = domain.upper else {
                    throw rationalAlgebraFailure("Native chart composition requires every finite original bound.")
                }
                let coordinate = try ExactIntersectionPolynomial.coordinate(variableCount: 4, at: axis, usage: &usage)
                polynomials.append(try coordinate.subtracting(.constant(variableCount: 4, value: lower, usage: &usage), usage: &usage))
                polynomials.append(try coordinate.subtracting(.constant(variableCount: 4, value: upper, usage: &usage), usage: &usage))
                instructions.append(.sign(polynomial: binding.boundStart + axis * 2, .negative))
                instructions.append(.not); instructions.append(.and)
                instructions.append(.sign(polynomial: binding.boundStart + axis * 2 + 1,
                    binding.finalUpper[axis] ? .positive : .negative))
                if binding.finalUpper[axis] { instructions.append(.not) }
                instructions.append(.and)
            }
            polynomials.append(contentsOf: binding.guardedRankWitnesses.normalizedEquations)
            if let corner = binding.sourceCornerZeroSet {
                try usage.consumeWork(corner.consequences.count)
                polynomials.append(contentsOf: corner.consequences)
            }
            instructions.append(.or)
        }
        try RationalAlgebraStorage.retain(lawCount, of: Bool.self, usage: &usage)
        try usage.consumeWork(lawCount)
        var boundedZeroEquations = Array(repeating: false, count: lawCount)
        for binding in bindings {
            try intersectionAlgebraStep(&usage)
            if !binding.excludedByUpperBoundary, let corner = binding.sourceCornerZeroSet {
                boundedZeroEquations[binding.equationStart + corner.equationIndex] = true
            }
        }
        try RationalAlgebraStorage.retain(lawCount, of: Int.self, usage: &usage)
        try RationalAlgebraStorage.retain(lawCount, of: ExactIntersectionPolynomial.self, usage: &usage)
        try RationalAlgebraStorage.retain(lawCount, of: ExactRationalCoefficient.self, usage: &usage)
        var units: [ExactRationalCoefficient] = []; units.reserveCapacity(lawCount)
        var originalToIssued: [Int] = []; originalToIssued.reserveCapacity(lawCount)
        var issued: [ExactIntersectionPolynomial] = []; issued.reserveCapacity(lawCount)
        for (original, polynomial) in polynomials.enumerated() {
            let leading = try polynomial.leading(usage: &usage)
            let normalized: ExactIntersectionPolynomial
            if let leading {
                normalized = try polynomial.scaled(by: .one.divided(by: leading.coefficient, usage: &usage), usage: &usage)
            } else { normalized = polynomial }
            units.append(leading?.coefficient ?? .one)
            if boundedZeroEquations[original] {
                // -2 requires the retained bounded branch proof, never a fixed sign.
                try intersectionAlgebraStep(&usage)
                originalToIssued.append(-2)
                continue
            }
            var equal: Int?
            for (ordinal, retained) in issued.enumerated() {
                try intersectionAlgebraStep(&usage)
                if try normalized.matches(retained, usage: &usage) { equal = ordinal; break }
            }
            if let equal { originalToIssued.append(equal) }
            else { originalToIssued.append(issued.count); issued.append(normalized) }
        }
        let witnessCapacity = try rationalAlgebraCount(charts.count, 4, multiply: true)
        try RationalAlgebraStorage.retain(witnessCapacity, of: Int.self, usage: &usage)
        try RationalAlgebraStorage.retain(charts.count, of: Int.self, usage: &usage)
        try RationalAlgebraStorage.retain(9, of: ExactIntersectionPolynomial.self, usage: &usage)
        var witnesses: [Int] = []; witnesses.reserveCapacity(witnessCapacity)
        var factors: [Int] = []; factors.reserveCapacity(charts.count)
        var necessary: [ExactIntersectionPolynomial] = []; necessary.reserveCapacity(9)
        var finite = effectiveDomains != nil
        for axis in 0..<4 {
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
                        for other in 0..<4 where other != axis {
                            try intersectionAlgebraStep(&usage)
                            if try power.exponent(at: other) != 0 { univariate = false }
                        }
                    }
                    if univariate { witness = ordinal; break }
                }
                guard let witness else { finite = false; break }
                witnesses.append(witness)
                let factor = originalToIssued[witness]
                guard factor >= 0 else { finite = false; break }
                var retained = false
                for existing in factors { try intersectionAlgebraStep(&usage); if existing == factor { retained = true; break } }
                if !retained { factors.append(factor) }
            }
            guard finite, !factors.isEmpty else { finite = false; break }
            var product = try ExactIntersectionPolynomial.constant(variableCount: 4, value: .one, usage: &usage)
            for factor in factors { product = try product.multiplied(by: issued[factor], usage: &usage) }
            necessary.append(product)
        }
        if !finite { witnesses.removeAll(keepingCapacity: true); necessary.removeAll(keepingCapacity: true) }
        let commonNecessary = try commonNecessaryEquations(bindings: bindings, usage: &usage)
        let commonNecessaryStart = necessary.count
        try usage.consumeWork(commonNecessary.equations.count)
        necessary.append(contentsOf: commonNecessary.equations)
        let necessaryIdeal = try ExactIntersectionIdeal.prepare(equations: necessary, variableCount: 4, usage: &usage)
        try RationalAlgebraStorage.retain(issued.count, of: Int.self, usage: &usage)
        try RationalAlgebraStorage.retain(issued.count, of: OriginalPolynomialPredicate.Sign.self, usage: &usage)
        try RationalAlgebraStorage.retain(lawCount, of: OriginalPolynomialPredicate.Sign.self, usage: &usage)
        try RationalAlgebraStorage.retain(issued.count, of: ExactIntersectionPolynomial.self, usage: &usage)
        try usage.consumeWork(try rationalAlgebraCount(rationalAlgebraCount(issued.count, 2, multiply: true), lawCount))
        var issuedToPhysical = Array(repeating: -1, count: issued.count)
        var issuedFixedSigns = Array(repeating: OriginalPolynomialPredicate.Sign.zero, count: issued.count)
        var fixedSigns = Array(repeating: OriginalPolynomialPredicate.Sign.zero, count: lawCount)
        var physical: [ExactIntersectionPolynomial] = []; physical.reserveCapacity(issued.count)
        for logical in issued.indices {
            try intersectionAlgebraStep(&usage)
            let mapped: ExactIntersectionPolynomial
            if necessaryIdeal.reducedBasis.isEmpty { mapped = issued[logical] }
            else { mapped = try ExactIntersectionGroebnerBasis.reduced(issued[logical], by: necessaryIdeal.reducedBasis, usage: &usage) }
            if mapped.isZero || mapped.isConstant {
                if let leading = try mapped.leading(usage: &usage) {
                    issuedFixedSigns[logical] = leading.coefficient.isNegative ? .negative : .positive
                }
                continue
            }
            var existing: Int?
            for ordinal in physical.indices {
                try intersectionAlgebraStep(&usage)
                if try mapped.matches(physical[ordinal], usage: &usage) { existing = ordinal; break }
            }
            if let existing { issuedToPhysical[logical] = existing }
            else {
                try intersectionAlgebraStep(&usage)
                issuedToPhysical[logical] = physical.count; physical.append(mapped)
            }
        }
        for original in originalToIssued.indices {
            try intersectionAlgebraStep(&usage)
            let logical = originalToIssued[original]
            if logical == -2 { continue }
            fixedSigns[original] = issuedFixedSigns[logical]
            originalToIssued[original] = issuedToPhysical[logical]
        }
        for index in instructions.indices {
            try intersectionAlgebraStep(&usage)
            if case .sign(let original, let sign) = instructions[index] {
                let actual: OriginalPolynomialPredicate.Sign
                if units[original].isNegative {
                    switch sign { case .positive: actual = .negative; case .negative: actual = .positive; case .zero: actual = .zero }
                } else { actual = sign }
                let mapped = originalToIssued[original]
                guard mapped != -2 else { throw rationalAlgebraFailure("A bounded corner equation escaped its original chart clause.") }
                instructions[index] = mapped >= 0 ? .sign(polynomial: mapped, actual) : .literal(fixedSigns[original] == actual)
            }
        }
        let program = try OriginalPolynomialPredicate(polynomialCount: physical.count, instructions: instructions, usage: &usage)
        // Shared source laws are necessary without proving finiteness. Only the
        // exact necessary ideal's finite classification enables prefix exclusion.
        let ambient = try OriginalRationalIntersectionCells.prepare(equations: necessaryIdeal.reducedBasis, variableCount: 4,
            exactDomains: effectiveDomains ?? requestedDomains, partitionPolynomials: physical,
            thomEncoding: true, pruneExcludedPrefixes: necessaryIdeal.classification != .positiveDimensional,
            maximumDepth: maximumDepth, usage: &usage)
        let selected = try ambient.selecting(program.original, usage: &usage)
        try RationalAlgebraStorage.retain(selected.cells.count, of: Int.self, usage: &usage)
        try RationalAlgebraStorage.retain(selected.cells.count, of: Int.self, usage: &usage)
        var owners = Array(repeating: -1, count: selected.cells.count)
        var originalRanks = Array(repeating: 0, count: selected.cells.count)
        for index in selected.solutionCells {
            let signs = selected.cells[index].signs, offset = selected.partitionSignOffset
            func originalSign(_ original: Int) throws -> ExactAlgebraicRealRoot.Sign {
                let physicalOrdinal = originalToIssued[original]
                guard physicalOrdinal != -2 else { throw rationalAlgebraFailure("A bounded corner equation cannot supply a global sign.") }
                let sign = physicalOrdinal >= 0 ? signs[offset + physicalOrdinal] : fixedSigns[original].original
                guard units[original].isNegative else { return sign }
                switch sign { case .positive: return .negative; case .negative: return .positive; case .zero: return .zero }
            }
            for (ordinal, binding) in bindings.enumerated() {
                try intersectionAlgebraStep(&usage)
                if binding.excludedByUpperBoundary { continue }
                var included = true
                for axis in 0..<4 {
                    try intersectionAlgebraStep(&usage)
                    if axis < 3 {
                        if let corner = binding.sourceCornerZeroSet, corner.equationIndex == axis {
                            for factor in corner.consequences.indices {
                                try intersectionAlgebraStep(&usage)
                                if try originalSign(binding.cornerStart + factor) != .zero { included = false }
                            }
                        } else if try originalSign(binding.equationStart + axis) != .zero { included = false }
                    }
                    let lower = try originalSign(binding.boundStart + axis * 2)
                    let upper = try originalSign(binding.boundStart + axis * 2 + 1)
                    if lower == .negative || (binding.finalUpper[axis] ? upper == .positive : upper != .negative) { included = false }
                }
                for guardIndex in 0..<2 {
                    if try originalSign(binding.equationStart + 3 + guardIndex) == .zero { included = false }
                }
                if included {
                    guard owners[index] == -1 else { throw rationalAlgebraFailure("Two original charts own one common parameter cell.") }
                    owners[index] = ordinal
                    for (minorOrdinal, minor) in binding.jacobian.minors.enumerated() {
                        try intersectionAlgebraStep(&usage)
                        if try originalSign(binding.minorStart + minorOrdinal) != .zero {
                            originalRanks[index] = max(originalRanks[index], minor.order)
                        }
                    }
                }
            }
            guard owners[index] >= 0 else { throw rationalAlgebraFailure("A selected common parameter cell lost its original chart owner.") }
        }
        let joins = try OriginalRationalIntersectionIncidence.prepare(partition: selected, maximumDepth: maximumDepth, usage: &usage)
        let components = try joins.connectedComponents(usage: &usage)
        guard components.components.count <= maximumComponentCount else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Native composed components exceed the cumulative result ceiling.")
        }
        let result = Self(charts: charts, nativeDomains: nativeDomains, requestedDomains: requestedDomains,
            effectiveDomains: effectiveDomains, laws: physical, predicate: program, partition: selected,
            incidence: joins, connected: components, chartOwners: owners, ranks: originalRanks,
            originalLawOrdinals: originalToIssued, originalLawUnits: units, originalLawFixedSigns: fixedSigns,
            finiteCoordinateWitnesses: witnesses, necessaryCoordinateEquations: necessary, necessaryIdeal: necessaryIdeal,
            commonNecessaryEquationStart: commonNecessaryStart, necessaryChartWitnesses: commonNecessary.witnesses, sourceBindings: bindings, originalLaws: polynomials,
            maximumComponentCount: maximumComponentCount)
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }
    private static func commonNecessaryEquations<B: ExactScalarAdmission & ~Copyable>(bindings: [Binding],
        usage: inout B) throws -> (equations: [ExactIntersectionPolynomial], witnesses: [[Int]]) {
        try RationalAlgebraStorage.retain(5, of: ExactIntersectionPolynomial.self, usage: &usage)
        try RationalAlgebraStorage.retain(5, of: [Int].self, usage: &usage)
        var result: [ExactIntersectionPolynomial] = []; result.reserveCapacity(5)
        var witnesses: [[Int]] = []; witnesses.reserveCapacity(5)
        var first: Int?
        for index in bindings.indices {
            try intersectionAlgebraStep(&usage)
            if !bindings[index].excludedByUpperBoundary { first = index; break }
        }
        guard let first else { return (result,witnesses) }
        func source(_ binding: Binding, _ ordinal: Int) -> ExactIntersectionPolynomial {
            ordinal < 3 ? binding.guardedEquations.normalizedEquations[ordinal]
                : binding.sourceZeroSet!.consequences[ordinal - 3]
        }
        func normalized(_ original: ExactIntersectionPolynomial, usage: inout B) throws -> ExactIntersectionPolynomial {
            if let leading = try original.leading(usage: &usage) {
                return try original.scaled(by: .one.divided(by: leading.coefficient, usage: &usage), usage: &usage)
            }
            return original
        }
        let candidateCount = try rationalAlgebraCount(3, bindings[first].sourceZeroSet?.consequences.count ?? 0)
        guard candidateCount <= 5 else { throw rationalAlgebraFailure("Native source zero consequences exceed their proved two-factor contract.") }
        for candidateOrdinal in 0..<candidateCount {
            let candidate = try normalized(source(bindings[first], candidateOrdinal), usage: &usage)
            if candidate.isZero { continue }
            var duplicate = false
            for retained in result {
                try intersectionAlgebraStep(&usage)
                if try candidate.matches(retained, usage: &usage) { duplicate = true; break }
            }
            if duplicate { continue }
            try RationalAlgebraStorage.retain(bindings.count, of: Int.self, usage: &usage)
            try usage.consumeWork(bindings.count)
            var row = Array(repeating: -1, count: bindings.count)
            var common = true
            for index in bindings.indices {
                try intersectionAlgebraStep(&usage)
                if bindings[index].excludedByUpperBoundary { continue }
                let count = try rationalAlgebraCount(3, bindings[index].sourceZeroSet?.consequences.count ?? 0)
                guard count <= 5 else { throw rationalAlgebraFailure("Native source zero consequences lost their original two-factor contract.") }
                for ordinal in 0..<count {
                    let original = try normalized(source(bindings[index], ordinal), usage: &usage)
                    if try candidate.matches(original, usage: &usage) { row[index] = ordinal; break }
                }
                if row[index] < 0 { common = false; break }
            }
            if common {
                try intersectionAlgebraStep(&usage)
                result.append(candidate); witnesses.append(row)
            }
        }
        return (result,witnesses)
    }

}
