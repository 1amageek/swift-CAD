import CADCore

/// One exact XYZ-prefix partition of the piecewise original Native source graph.
package struct NativeSurfaceSurfaceCommonGraph {
    package let partition: OriginalRationalIntersectionCells
    package let ideal: ExactIntersectionIdeal
    package let guardedEquations: [OriginalGuardedIntersectionEquations]

    package static func prepare<B: ExactScalarAdmission & ~Copyable>(coverage: NativeSurfaceSurfaceCommonCoverage,
        conditions: [OriginalIntersectionCellCondition], maximumDepth: Int,
        usage: inout B) throws -> Self {
        guard let effective = coverage.effectiveDomains else {
            throw rationalAlgebraFailure("Common SSI graph requires its complete original selected product.")
        }
        try RationalAlgebraStorage.retain(4, of: Int.self, usage: &usage)
        let axes = [3,4,5,6]
        let chartLawCount = try rationalAlgebraCount(coverage.charts.count, 3, multiply: true)
        try RationalAlgebraStorage.retain(chartLawCount, of: ExactIntersectionPolynomial.self, usage: &usage)
        var graphLaws: [ExactIntersectionPolynomial] = []; graphLaws.reserveCapacity(chartLawCount)
        try RationalAlgebraStorage.retain(coverage.charts.count, of: OriginalGuardedIntersectionEquations.self, usage: &usage)
        var guardedEquations: [OriginalGuardedIntersectionEquations] = []; guardedEquations.reserveCapacity(coverage.charts.count)
        for chart in coverage.charts {
            let weight = try ExactIntersectionPolynomial.embedding(chart.first.homogeneous[3], variableCount: 7,
                uCoordinate: 3, vCoordinate: 4, usage: &usage)
            try RationalAlgebraStorage.retain(3, of: ExactIntersectionPolynomial.self, usage: &usage)
            var originalGraph: [ExactIntersectionPolynomial] = []; originalGraph.reserveCapacity(3)
            for axis in 0..<3 {
                let coordinate = try ExactIntersectionPolynomial.coordinate(variableCount: 7, at: axis, usage: &usage)
                let position = try ExactIntersectionPolynomial.embedding(chart.first.homogeneous[axis], variableCount: 7,
                    uCoordinate: 3, vCoordinate: 4, usage: &usage)
                originalGraph.append(try coordinate.multiplied(by: weight, usage: &usage).subtracting(position, usage: &usage))
            }
            try RationalAlgebraStorage.retain(2, of: ExactIntersectionPolynomial.self, usage: &usage)
            var guards: [ExactIntersectionPolynomial] = []; guards.reserveCapacity(2)
            for guardPolynomial in chart.system.denominatorGuards {
                guards.append(try guardPolynomial.remapped(to: 7, coordinates: axes, usage: &usage))
            }
            let guarded = try OriginalGuardedIntersectionEquations.prepare(equations: originalGraph,
                denominatorGuards: guards, variableCount: 7, usage: &usage)
            guard guarded.normalizedEquations.count == 3 else {
                throw rationalAlgebraFailure("Common SSI graph normalization lost its original three equation ordinals.")
            }
            guardedEquations.append(guarded)
            graphLaws.append(contentsOf: guarded.normalizedEquations)
        }
        // Every selected branch zeros each product. These constraints reduce the
        // common ideal only; the full source DNF remains the selection authority.
        let necessaryCount = try rationalAlgebraCount(6, coverage.necessaryCoordinateEquations.count)
        try RationalAlgebraStorage.retain(necessaryCount, of: ExactIntersectionPolynomial.self, usage: &usage)
        var necessary: [ExactIntersectionPolynomial] = []; necessary.reserveCapacity(necessaryCount)
        try RationalAlgebraStorage.retain(coverage.charts.count, of: ExactIntersectionPolynomial.self, usage: &usage)
        var factors: [ExactIntersectionPolynomial] = []; factors.reserveCapacity(coverage.charts.count)
        for axis in 0..<6 {
            factors.removeAll(keepingCapacity: true)
            var product = try ExactIntersectionPolynomial.constant(variableCount: 7, value: .one, usage: &usage)
            for ordinal in coverage.charts.indices {
                let binding = coverage.sourceBindings[ordinal]
                if binding.excludedByUpperBoundary { continue }
                let factor: ExactIntersectionPolynomial
                if axis < 3 {
                    factor = try coverage.originalLaws[binding.equationStart + axis]
                        .remapped(to: 7, coordinates: axes, usage: &usage)
                } else { factor = graphLaws[ordinal * 3 + axis - 3] }
                let normalized: ExactIntersectionPolynomial
                if let leading = try factor.leading(usage: &usage) {
                    normalized = try factor.scaled(by: .one.divided(by: leading.coefficient, usage: &usage), usage: &usage)
                } else { normalized = factor }
                var retained = false
                for existing in factors {
                    try intersectionAlgebraStep(&usage)
                    if try normalized.matches(existing, usage: &usage) { retained = true; break }
                }
                if !retained {
                    factors.append(normalized)
                    product = try product.multiplied(by: normalized, usage: &usage)
                }
            }
            necessary.append(product)
        }
        for equation in coverage.necessaryCoordinateEquations {
            try intersectionAlgebraStep(&usage)
            necessary.append(try equation.remapped(to: 7, coordinates: axes, usage: &usage))
        }
        let ideal = try ExactIntersectionIdeal.prepare(equations: necessary, variableCount: 7, usage: &usage)
        guard coverage.partition.tower.variableCount == 4, coverage.partition.tower.hasThomEncoding,
            coverage.partition.tower.levels.count == 4,
            conditions.count == coverage.partition.solutionCells.count else {
            throw rationalAlgebraFailure("Common SSI graph witnesses require the complete original derivative-closed four-UV tower.")
        }
        for ordinal in conditions.indices {
            try intersectionAlgebraStep(&usage)
            guard conditions[ordinal].variableCount == 4,
                conditions[ordinal].cellIndex == coverage.partition.solutionCells[ordinal] else {
                throw rationalAlgebraFailure("Common SSI graph conditions lost their original full-tuple cell ordering.")
            }
        }
        var witnessCapacity = 0
        for level in coverage.partition.tower.levels {
            try intersectionAlgebraStep(&usage)
            witnessCapacity = try rationalAlgebraCount(witnessCapacity, level.sources.count)
        }
        try RationalAlgebraStorage.retain(witnessCapacity, of: ExactIntersectionPolynomial.self, usage: &usage)
        var originalWitnesses: [ExactIntersectionPolynomial] = []; originalWitnesses.reserveCapacity(witnessCapacity)
        // Every complete condition reads these same global sources; only its
        // cell signs vary. Retain the polynomial union without choosing a cell.
        for level in coverage.partition.tower.levels.reversed() {
            for source in level.sources {
                try intersectionAlgebraStep(&usage)
                var duplicate = false
                for retained in originalWitnesses {
                    try intersectionAlgebraStep(&usage)
                    if try source.matches(retained, usage: &usage) { duplicate = true; break }
                }
                if !duplicate {
                    try intersectionAlgebraStep(&usage)
                    originalWitnesses.append(source)
                }
            }
        }
        let graphStart = coverage.laws.count
        let logicalCount = try rationalAlgebraCount(graphStart, chartLawCount)
        try RationalAlgebraStorage.retain(logicalCount, of: Int.self, usage: &usage)
        try RationalAlgebraStorage.retain(logicalCount, of: OriginalPolynomialPredicate.Sign.self, usage: &usage)
        try usage.consumeWork(logicalCount)
        var physicalOrdinals = Array(repeating: -1, count: logicalCount)
        try usage.consumeWork(logicalCount)
        var fixedSigns = Array(repeating: OriginalPolynomialPredicate.Sign.zero, count: logicalCount)
        var capacity = logicalCount
        capacity = try rationalAlgebraCount(capacity, witnessCapacity)
        try RationalAlgebraStorage.retain(capacity, of: ExactIntersectionPolynomial.self, usage: &usage)
        var laws: [ExactIntersectionPolynomial] = []; laws.reserveCapacity(capacity)
        func issue(_ mapped: ExactIntersectionPolynomial, logical: Int, usage: inout B) throws {
            try intersectionAlgebraStep(&usage)
            if mapped.isZero || mapped.isConstant {
                if let leading = try mapped.leading(usage: &usage) {
                    fixedSigns[logical] = leading.coefficient.isNegative ? .negative : .positive
                }
                return
            }
            for ordinal in laws.indices {
                try intersectionAlgebraStep(&usage)
                if try mapped.matches(laws[ordinal], usage: &usage) {
                    physicalOrdinals[logical] = ordinal
                    return
                }
            }
            try intersectionAlgebraStep(&usage)
            physicalOrdinals[logical] = laws.count
            laws.append(mapped)
        }
        for logical in coverage.laws.indices {
            let original = try coverage.laws[logical].remapped(to: 7, coordinates: axes, usage: &usage)
            let mapped = try ExactIntersectionGroebnerBasis.reduced(original, by: ideal.reducedBasis, usage: &usage)
            try issue(mapped, logical: logical, usage: &usage)
        }
        for ordinal in graphLaws.indices {
            let mapped = try ExactIntersectionGroebnerBasis.reduced(graphLaws[ordinal], by: ideal.reducedBasis, usage: &usage)
            try issue(mapped, logical: graphStart + ordinal, usage: &usage)
        }
        for law in originalWitnesses {
            try intersectionAlgebraStep(&usage)
            let original = try law.remapped(to: 7, coordinates: axes, usage: &usage)
            let mapped = try ExactIntersectionGroebnerBasis.reduced(original, by: ideal.reducedBasis, usage: &usage)
            if mapped.isZero || mapped.isConstant { continue }
            var duplicate = false
            for retained in laws {
                try intersectionAlgebraStep(&usage)
                if try mapped.matches(retained, usage: &usage) { duplicate = true; break }
            }
            if !duplicate {
                try intersectionAlgebraStep(&usage)
                laws.append(mapped)
            }
        }
        let instructionCount = try rationalAlgebraCount(1,
            rationalAlgebraCount(coverage.charts.count, 46, multiply: true))
        try RationalAlgebraStorage.retain(instructionCount, of: OriginalPolynomialPredicate.Instruction.self, usage: &usage)
        var instructions: [OriginalPolynomialPredicate.Instruction] = []; instructions.reserveCapacity(instructionCount)
        func emit(_ instruction: OriginalPolynomialPredicate.Instruction, usage: inout B) throws {
            try intersectionAlgebraStep(&usage)
            instructions.append(instruction)
        }
        try emit(.literal(false), usage: &usage)
        func emitSign(_ logical: Int, _ sign: OriginalPolynomialPredicate.Sign, usage: inout B) throws {
            try intersectionAlgebraStep(&usage)
            let physical = physicalOrdinals[logical]
            if physical >= 0 { try emit(.sign(polynomial: physical, sign), usage: &usage) }
            else { try emit(.literal(fixedSigns[logical] == sign), usage: &usage) }
        }
        func atom(_ original: Int, _ sign: OriginalPolynomialPredicate.Sign, usage: inout B) throws {
            try intersectionAlgebraStep(&usage)
            let actual: OriginalPolynomialPredicate.Sign
            if coverage.originalLawUnits[original].isNegative {
                switch sign { case .negative: actual = .positive; case .positive: actual = .negative; case .zero: actual = .zero }
            } else { actual = sign }
            let physical = coverage.originalLawOrdinals[original]
            guard physical != -2 else { throw rationalAlgebraFailure("Common graph bounded zero evidence escaped its source chart clause.") }
            if physical >= 0 { try emitSign(physical, actual, usage: &usage) }
            else { try emit(.literal(coverage.originalLawFixedSigns[original] == actual), usage: &usage) }
        }
        for ordinal in coverage.charts.indices {
            try intersectionAlgebraStep(&usage)
            let binding = coverage.sourceBindings[ordinal]
            if binding.excludedByUpperBoundary { continue }
            try emit(.literal(true), usage: &usage)
            for axis in 0..<3 {
                if let corner = binding.sourceCornerZeroSet, corner.equationIndex == axis {
                    for factor in corner.consequences.indices {
                        try atom(binding.cornerStart + factor, .zero, usage: &usage); try emit(.and, usage: &usage)
                    }
                } else { try atom(binding.equationStart + axis, .zero, usage: &usage); try emit(.and, usage: &usage) }
            }
            for axis in 0..<2 {
                try atom(binding.equationStart + 3 + axis, .zero, usage: &usage); try emit(.not, usage: &usage); try emit(.and, usage: &usage)
            }
            for axis in 0..<4 {
                try atom(binding.boundStart + axis * 2, .negative, usage: &usage); try emit(.not, usage: &usage); try emit(.and, usage: &usage)
                try atom(binding.boundStart + axis * 2 + 1, binding.finalUpper[axis] ? .positive : .negative, usage: &usage)
                if binding.finalUpper[axis] { try emit(.not, usage: &usage) }; try emit(.and, usage: &usage)
            }
            for axis in 0..<3 {
                try emitSign(graphStart + ordinal * 3 + axis, .zero, usage: &usage); try emit(.and, usage: &usage)
            }
            try emit(.or, usage: &usage)
        }
        let predicate = try OriginalPolynomialPredicate(polynomialCount: laws.count, instructions: instructions, usage: &usage)
        try RationalAlgebraStorage.retain(7, of: OriginalRationalParameterDomain.self, usage: &usage)
        var domains: [OriginalRationalParameterDomain] = []; domains.reserveCapacity(7)
        domains.append(contentsOf: try originalImageDomains(charts: coverage.charts, usage: &usage))
        domains.append(contentsOf: effective)
        let ambient = try OriginalRationalIntersectionCells.prepare(equations: ideal.reducedBasis, variableCount: 7,
            exactDomains: domains, partitionPolynomials: laws, thomEncoding: true,
            pruneExcludedPrefixes: true, pruneDomainPrefixes: true, maximumDepth: maximumDepth, usage: &usage)
        let partition = try ambient.selecting(predicate.original, usage: &usage)
        return .init(partition: partition, ideal: ideal, guardedEquations: guardedEquations)
    }

    /// Positive original rational basis weights make these source extrema exact
    /// necessary graph bounds throughout the retained closed native charts.
    private static func originalImageDomains<B: ExactScalarAdmission & ~Copyable>(charts: [NativeSurfaceSurfaceSourceChart],
        usage: inout B) throws -> [OriginalRationalParameterDomain] {
        try RationalAlgebraStorage.retain(6, of: Double.self, usage: &usage)
        var lower = Array(repeating: Double.infinity, count: 3)
        var upper = Array(repeating: -Double.infinity, count: 3)
        for chart in charts {
            try intersectionAlgebraStep(&usage)
            let source = chart.first.source
            guard !source.isUPeriodic, !source.isVPeriodic, !source.controlPoints.isEmpty,
                source.controlPoints.count == source.weights.count else {
                throw rationalAlgebraFailure("Common SSI image bounds require their finite nonperiodic original source.")
            }
            for row in source.controlPoints.indices {
                try intersectionAlgebraStep(&usage)
                guard !source.controlPoints[row].isEmpty, source.controlPoints[row].count == source.weights[row].count else {
                    throw rationalAlgebraFailure("Common SSI image bounds lost the original control-point and weight ownership.")
                }
                for index in source.controlPoints[row].indices {
                    try intersectionAlgebraStep(&usage)
                    let weight = source.weights[row][index]
                    guard weight.isFinite, weight > 0 else {
                        throw rationalAlgebraFailure("Common SSI image bounds require strictly positive original weights.")
                    }
                    let point = source.controlPoints[row][index]
                    for axis in 0..<3 {
                        try intersectionAlgebraStep(&usage)
                        let coordinate: Double
                        switch axis { case 0: coordinate = point.x; case 1: coordinate = point.y; default: coordinate = point.z }
                        guard coordinate.isFinite else {
                            throw rationalAlgebraFailure("Common SSI image bounds require finite original control points.")
                        }
                        // Ordering finite source values does not round or expand their extrema.
                        lower[axis] = min(lower[axis], coordinate)
                        upper[axis] = max(upper[axis], coordinate)
                    }
                }
            }
        }
        try RationalAlgebraStorage.retain(3, of: OriginalRationalParameterDomain.self, usage: &usage)
        var result: [OriginalRationalParameterDomain] = []; result.reserveCapacity(3)
        for axis in 0..<3 {
            result.append(try .init(lower: .originalDouble(lower[axis], usage: &usage),
                upper: .originalDouble(upper[axis], usage: &usage), usage: &usage))
        }
        return result
    }
}
