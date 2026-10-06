/// Exact sign-preserving predicate normalization under retained original guards.
package struct OriginalPositiveGuardPolynomialReduction: Sendable {
    package let candidateCoordinate: Int
    package let equationIndex: Int
    package let guardIndex: Int
    package let guardSign: ExactAlgebraicRealRoot.Sign
    package let multiplier: ExactIntersectionPolynomial
    package let constantCoefficient: ExactIntersectionPolynomial
    package let predicateIndexes: [Int]
    package let multiplierPowers: [Int]

    private init(candidateCoordinate: Int, equationIndex: Int, guardIndex: Int,
        guardSign: ExactAlgebraicRealRoot.Sign, multiplier: ExactIntersectionPolynomial,
        constantCoefficient: ExactIntersectionPolynomial, predicateIndexes: [Int], multiplierPowers: [Int]) {
        self.candidateCoordinate = candidateCoordinate; self.equationIndex = equationIndex
        self.guardIndex = guardIndex; self.guardSign = guardSign; self.multiplier = multiplier
        self.constantCoefficient = constantCoefficient
        self.predicateIndexes = predicateIndexes; self.multiplierPowers = multiplierPowers
    }

    /// On closed original support, a nonzero constant B rules out A=0.
    /// Continuity of the issued strict A sign therefore retains that same sign.
    package static func prepareFreeSupport<B: RationalAlgebraAdmitting>(
        polynomials: inout [ExactIntersectionPolynomial], source: OriginalIntersectionCellCondition,
        usage: inout B) throws -> Self? {
        guard let first = polynomials.first else { return nil }
        try RationalAlgebraStorage.retain(source.variableCount, of: Int.self, usage: &usage)
        let free = Array(0..<source.variableCount)
        let axis = source.variableCount - 1
        for equationIndex in source.signs.indices where source.signs[equationIndex] == .zero {
            let equation = try source.polynomials[equationIndex].remapped(to: first.variableCount,
                coordinates: free, usage: &usage)
            let coefficients = try equation.axisCoefficients(at: axis, usage: &usage)
            guard coefficients.count == 2, coefficients[0].isConstant, !coefficients[0].isZero,
                !coefficients[1].isConstant else { continue }
            let leading = coefficients[1]
            for guardIndex in source.signs.indices where source.signs[guardIndex] != .zero {
                let guardPolynomial = try source.polynomials[guardIndex].remapped(to: first.variableCount,
                    coordinates: free, usage: &usage)
                guard try guardPolynomial.matches(leading, usage: &usage) else { continue }
                let negative = source.signs[guardIndex] == .negative
                let multiplier = negative ? try leading.scaled(by: .one.negated, usage: &usage) : leading
                let negativeConstant = try coefficients[0].scaled(by: .one.negated, usage: &usage)
                try RationalAlgebraStorage.retain(polynomials.count, of: Int.self, usage: &usage)
                try RationalAlgebraStorage.retain(polynomials.count, of: Int.self, usage: &usage)
                var indexes: [Int] = [], powers: [Int] = []
                for index in polynomials.indices {
                    let values = try polynomials[index].axisCoefficients(at: axis, usage: &usage)
                    let degree = values.count - 1
                    guard degree > 0, let last = values.last else { continue }
                    var substituted = last, leadingPower = leading
                    for ordinal in stride(from: degree - 1, through: 0, by: -1) {
                        try intersectionAlgebraStep(&usage)
                        substituted = try substituted.multiplied(by: negativeConstant, usage: &usage)
                            .adding(values[ordinal].multiplied(by: leadingPower, usage: &usage), usage: &usage)
                        if ordinal > 0 { leadingPower = try leadingPower.multiplied(by: leading, usage: &usage) }
                    }
                    if negative && degree & 1 != 0 {
                        substituted = try substituted.scaled(by: .one.negated, usage: &usage)
                    }
                    polynomials[index] = substituted
                    indexes.append(index); powers.append(degree)
                }
                try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
                return Self(candidateCoordinate: axis, equationIndex: equationIndex, guardIndex: guardIndex,
                    guardSign: source.signs[guardIndex], multiplier: multiplier,
                    constantCoefficient: coefficients[0], predicateIndexes: indexes, multiplierPowers: powers)
            }
        }
        return nil
    }

    package static func prepare<B: RationalAlgebraAdmitting>(polynomials: inout [ExactIntersectionPolynomial],
        original: [ExactIntersectionPolynomial], source: OriginalIntersectionCellCondition, candidateCoordinates: [Int],
        candidateCoordinate: Int, ideal: ExactIntersectionIdeal, radiusIndex: Int, usage: inout B) throws -> Self? {
        let sourceSigns = source.signs
        guard original.count == polynomials.count, sourceSigns.count <= original.count,
            radiusIndex == sourceSigns.count, candidateCoordinates.count == source.variableCount,
            let first = original.first, candidateCoordinate >= source.variableCount,
            candidateCoordinate == first.variableCount - 1 else {
            throw rationalAlgebraFailure("Guarded predicate reduction requires the complete bound candidate conjunction.")
        }
        for index in source.polynomials.indices {
            guard try source.polynomials[index].remapped(to: first.variableCount, coordinates: candidateCoordinates,
                usage: &usage).matches(original[index], usage: &usage) else {
                throw rationalAlgebraFailure("Guarded predicate reduction has a foreign original source condition.")
            }
        }
        guard ideal.variableCount == first.variableCount else {
            throw rationalAlgebraFailure("Guarded predicate reduction has a foreign zero-condition ideal.")
        }
        try RationalAlgebraStorage.retain(source.variableCount, of: Int.self, usage: &usage)
        let free = Array(0..<source.variableCount)
        var generator = 0
        for index in source.polynomials.indices where sourceSigns[index] == .zero && !source.polynomials[index].isZero {
            let next = try rationalAlgebraCount(generator, 1)
            guard next < ideal.originalEquations.count,
                try ideal.originalEquations[generator].matches(original[index], usage: &usage),
                try source.polynomials[index].remapped(to: first.variableCount, coordinates: free,
                    usage: &usage).matches(ideal.originalEquations[next], usage: &usage) else {
                throw rationalAlgebraFailure("Guarded predicate reduction replaced an original candidate/free zero condition.")
            }
            generator = try rationalAlgebraCount(next, 1)
        }
        guard generator == ideal.originalEquations.count else {
            throw rationalAlgebraFailure("Guarded predicate reduction used an unrelated ideal equation.")
        }
        for equationIndex in sourceSigns.indices where sourceSigns[equationIndex] == .zero {
            try intersectionAlgebraStep(&usage)
            let coefficients = try original[equationIndex].axisCoefficients(at: candidateCoordinate, usage: &usage)
            guard coefficients.count == 2, !coefficients[1].isZero, !coefficients[1].isConstant else { continue }
            let leading = coefficients[1]
            for guardIndex in sourceSigns.indices where sourceSigns[guardIndex] != .zero {
                guard try original[guardIndex].matches(leading, usage: &usage) else { continue }
                let multiplier = sourceSigns[guardIndex] == .positive ? leading :
                    try leading.scaled(by: .one.negated, usage: &usage)
                try RationalAlgebraStorage.retain(polynomials.count, of: Int.self, usage: &usage)
                try RationalAlgebraStorage.retain(polynomials.count, of: Int.self, usage: &usage)
                var indexes: [Int] = [], powers: [Int] = []
                indexes.reserveCapacity(polynomials.count); powers.reserveCapacity(polynomials.count)
                for index in polynomials.indices {
                    try intersectionAlgebraStep(&usage)
                    if index == equationIndex {
                        polynomials[index] = try .zero(variableCount: first.variableCount)
                        continue
                    }
                    // Other zero conditions must remain genuine constraints.
                    // Reducing them by the whole source ideal would erase them.
                    let predicate = index < sourceSigns.count && sourceSigns[index] == .zero ?
                        original[index] : polynomials[index]
                    let values = try predicate.axisCoefficients(at: candidateCoordinate, usage: &usage)
                    let degree = values.count - 1
                    if degree <= 0 { polynomials[index] = predicate; continue }
                    guard let last = values.last else {
                        throw rationalAlgebraFailure("Guarded substitution lost an original predicate coefficient.")
                    }
                    let negativeConstant = try coefficients[0].scaled(by: .one.negated, usage: &usage)
                    var substituted = last, leadingPower = leading
                    for ordinal in stride(from: degree - 1, through: 0, by: -1) {
                        try intersectionAlgebraStep(&usage)
                        substituted = try substituted.multiplied(by: negativeConstant, usage: &usage)
                            .adding(values[ordinal].multiplied(by: leadingPower, usage: &usage), usage: &usage)
                        if ordinal > 0 { leadingPower = try leadingPower.multiplied(by: leading, usage: &usage) }
                    }
                    if sourceSigns[guardIndex] == .negative && degree & 1 != 0 {
                        substituted = try substituted.scaled(by: .one.negated, usage: &usage)
                    }
                    polynomials[index] = substituted
                    indexes.append(index); powers.append(degree)
                }
                for index in polynomials.indices {
                    try intersectionAlgebraStep(&usage)
                    polynomials[index] = try polynomials[index].lowered(to: first.variableCount - 1, usage: &usage)
                }
                try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
                return Self(candidateCoordinate: candidateCoordinate, equationIndex: equationIndex,
                    guardIndex: guardIndex, guardSign: sourceSigns[guardIndex], multiplier: multiplier,
                    constantCoefficient: coefficients[0], predicateIndexes: indexes, multiplierPowers: powers)
            }
        }
        return nil
    }
}
