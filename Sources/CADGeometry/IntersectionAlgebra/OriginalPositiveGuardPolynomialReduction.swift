import CADCore

/// Exact sign-preserving predicate normalization under retained original guards.
package struct OriginalPositiveGuardPolynomialReduction: Sendable {
    package let candidateCoordinate: Int
    package let equationIndex: Int
    package enum Authority: Sendable {
        case originalGuard(index: Int, sign: ExactAlgebraicRealRoot.Sign)
        case rationalLeadingCoefficient(ExactRationalCoefficient)

        var sign: ExactAlgebraicRealRoot.Sign {
            switch self {
            case .originalGuard(_, let sign): return sign
            case .rationalLeadingCoefficient(let coefficient):
                return coefficient.isPositive ? .positive : coefficient.isNegative ? .negative : .zero
            }
        }
    }
    package enum CoordinateTransport: Sendable {
        case identity
        /// Maps every original ring slot to a working slot, and back.
        case existentialSuffix(originalToWorking: [Int], workingToOriginal: [Int])
    }
    package let originalCandidateCoordinate: Int
    package let coordinateTransport: CoordinateTransport
    package let authority: Authority
    package let multiplier: ExactIntersectionPolynomial
    package let constantCoefficient: ExactIntersectionPolynomial
    package let predicateIndexes: [Int]
    package let multiplierPowers: [Int]

    private init(candidateCoordinate: Int, equationIndex: Int, authority: Authority,
        multiplier: ExactIntersectionPolynomial,
        originalCandidateCoordinate: Int? = nil, coordinateTransport: CoordinateTransport = .identity,
        constantCoefficient: ExactIntersectionPolynomial, predicateIndexes: [Int], multiplierPowers: [Int]) {
        self.candidateCoordinate = candidateCoordinate; self.equationIndex = equationIndex
        self.authority = authority; self.multiplier = multiplier
        self.originalCandidateCoordinate = originalCandidateCoordinate ?? candidateCoordinate
        self.coordinateTransport = coordinateTransport
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
                return Self(candidateCoordinate: axis, equationIndex: equationIndex,
                    authority: .originalGuard(index: guardIndex, sign: source.signs[guardIndex]), multiplier: multiplier,
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
        typealias Selection = (index: Int, coefficients: [ExactIntersectionPolynomial], authority: Authority)
        func selection(at axis: Int, original: [ExactIntersectionPolynomial], usage: inout B) throws -> Selection? {
            for index in sourceSigns.indices where sourceSigns[index] == .zero {
                try intersectionAlgebraStep(&usage)
                let coefficients = try original[index].axisCoefficients(at: axis, usage: &usage)
                guard coefficients.count == 2, !coefficients[1].isZero else { continue }
                let leading = coefficients[1]
                if leading.isConstant {
                    guard let value = try leading.leading(usage: &usage)?.coefficient, !value.isZero else {
                        throw rationalAlgebraFailure("Original candidate substitution lost its nonzero rational leading coefficient.")
                    }
                    return (index, coefficients, .rationalLeadingCoefficient(value))
                }
                for guardIndex in sourceSigns.indices where sourceSigns[guardIndex] != .zero {
                    if try original[guardIndex].matches(leading, usage: &usage) {
                        return (index, coefficients, .originalGuard(index: guardIndex, sign: sourceSigns[guardIndex]))
                    }
                }
            }
            return nil
        }
        func nonlinearCandidateDependence(_ polynomial: ExactIntersectionPolynomial, usage: inout B) throws -> Bool {
            for term in try polynomial.orderedTerms(usage: &usage) {
                var degree = 0
                for axis in (source.variableCount + 1)..<first.variableCount {
                    try intersectionAlgebraStep(&usage)
                    degree = try rationalAlgebraCount(degree, term.key.exponent(at: axis))
                    if degree > 1 { return true }
                }
            }
            return false
        }
        let legacy = try selection(at: candidateCoordinate, original: original, usage: &usage)
        var chosen = candidateCoordinate
        var chosenEquation: Int?
        var transport = CoordinateTransport.identity
        var workingOriginal = original
        // Preserve an existing strict original-guard proof and its ordering.
        let keepsOriginalGuard: Bool
        if let legacy, case .originalGuard = legacy.authority { keepsOriginalGuard = true }
        else { keepsOriginalGuard = false }
        if !keepsOriginalGuard {
            outer: for index in sourceSigns.indices where sourceSigns[index] == .zero {
                for coordinate in candidateCoordinates where coordinate > source.variableCount && coordinate != candidateCoordinate {
                    try intersectionAlgebraStep(&usage)
                    let coefficients = try original[index].axisCoefficients(at: coordinate, usage: &usage)
                    guard coefficients.count == 2, !coefficients[1].isZero, coefficients[1].isConstant,
                        try nonlinearCandidateDependence(coefficients[0], usage: &usage) else { continue }
                    chosen = coordinate
                    chosenEquation = index
                    break outer
                }
            }
        }
        if chosen != candidateCoordinate {
            // The original conjunction and source/ideal binding above precede
            // the paid bijection. Free coordinates and the radius never move.
            let count = first.variableCount
            try RationalAlgebraStorage.retain(try rationalAlgebraCount(count, count), of: Int.self, usage: &usage)
            try CurrentTaskCancellationChecker().checkCancellation()
            var forward: [Int] = [], inverse: [Int] = []
            forward.reserveCapacity(count); inverse.reserveCapacity(count)
            for axis in 0..<count {
                try intersectionAlgebraStep(&usage)
                forward.append(axis == chosen ? candidateCoordinate : axis > chosen ? axis - 1 : axis)
                inverse.append(axis == candidateCoordinate ? chosen : axis >= chosen ? axis + 1 : axis)
            }
            try CurrentTaskCancellationChecker().checkCancellation()
            guard chosen > source.variableCount, candidateCoordinate == count - 1 else {
                throw rationalAlgebraFailure("Original candidate transport crossed the free or radius prefix.")
            }
            for axis in 0..<count {
                try intersectionAlgebraStep(&usage)
                guard forward[axis] >= 0, forward[axis] < count, inverse[forward[axis]] == axis,
                    axis > source.variableCount || forward[axis] == axis else {
                    throw rationalAlgebraFailure("Original candidate transport is not a suffix bijection.")
                }
            }
            try RationalAlgebraStorage.retain(original.count, of: ExactIntersectionPolynomial.self, usage: &usage)
            var originals: [ExactIntersectionPolynomial] = []; originals.reserveCapacity(original.count)
            try RationalAlgebraStorage.retain(polynomials.count, of: ExactIntersectionPolynomial.self, usage: &usage)
            var transported: [ExactIntersectionPolynomial] = []; transported.reserveCapacity(polynomials.count)
            for index in original.indices {
                originals.append(try original[index].remapped(to: count, coordinates: forward, usage: &usage))
                transported.append(try polynomials[index].remapped(to: count, coordinates: forward, usage: &usage))
            }
            workingOriginal = originals
            polynomials = transported
            transport = .existentialSuffix(originalToWorking: forward, workingToOriginal: inverse)
        }
        let selected: Selection
        if chosen == candidateCoordinate {
            guard let legacy else { return nil }
            selected = legacy
        } else {
            guard let index = chosenEquation else {
                throw rationalAlgebraFailure("Original candidate transport lost its bound source equation.")
            }
            let coefficients = try workingOriginal[index].axisCoefficients(at: candidateCoordinate, usage: &usage)
            guard coefficients.count == 2, coefficients[1].isConstant,
                let value = try coefficients[1].leading(usage: &usage)?.coefficient, !value.isZero else {
                throw rationalAlgebraFailure("Original candidate transport changed its rational substitution authority.")
            }
            selected = (index, coefficients, .rationalLeadingCoefficient(value))
        }
        let equationIndex = selected.index, coefficients = selected.coefficients, authority = selected.authority
        let leading = coefficients[1]
        let multiplier = authority.sign == .positive ? leading :
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
            // Every other original zero remains a constraint after transport.
            let predicate = index < sourceSigns.count && sourceSigns[index] == .zero ?
                workingOriginal[index] : polynomials[index]
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
            if authority.sign == .negative && degree & 1 != 0 {
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
        try CurrentTaskCancellationChecker().checkCancellation()
        return Self(candidateCoordinate: candidateCoordinate, equationIndex: equationIndex,
            authority: authority, multiplier: multiplier, originalCandidateCoordinate: chosen,
            coordinateTransport: transport, constantCoefficient: coefficients[0],
            predicateIndexes: indexes, multiplierPowers: powers)
    }
}
