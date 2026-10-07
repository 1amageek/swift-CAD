import CADCore

/// Complete source-owned UV preimages at one retained exact surface station.
public struct OriginalNativeSurfaceSurfaceFiber: Sendable {
    public let source: OriginalNativeSurfaceSurfaceRelations
    public let surfaceRole: Int
    public let u: OriginalAlgebraicCoordinate
    public let v: OriginalAlgebraicCoordinate
    /// Coordinate order remains u1,v1,u2,v2, including every exceptional cell.
    public let relation: OriginalRealRelation
    /// Fixing both source coordinates fixes its exact XYZ, including collapsed sources.
    public var imageDimension: Int? { relation.cells.isEmpty ? nil : 0 }
}

extension OriginalNativeSurfaceSurfaceRelations {
    /// Algebraic stations retain their original ordered coefficient owners and both depth domains.
    public func fiber(surface: Int, u: OriginalAlgebraicCoordinate, v: OriginalAlgebraicCoordinate,
        maximumAlgebraicDepth: Int, maximumCoefficientDepth: Int,
        usage: OriginalRelationUsage) throws -> OriginalNativeSurfaceSurfaceFiber {
        var admission = try OriginalRelationDepthAdmission(base: usage, maximumDepth: maximumAlgebraicDepth,
            maximumCoefficientDepth: maximumCoefficientDepth)
        try intersectionAlgebraStep(&admission)
        guard (0...1).contains(surface) else { throw GeometryConversionError.invalidInput("An exact SSI fiber requires an original surface role.") }
        let retainedDepth = try retainedParameterDepth(usage: &admission)
        guard retainedDepth <= maximumAlgebraicDepth else {
            throw rationalAlgebraFailure("Ordered SSI fiber cannot reset its retained source relation depth.")
        }
        try RationalAlgebraStorage.retain(2, of: OriginalAlgebraicCoordinate.self, usage: &admission)
        let fixed = [u,v]
        for axis in 0..<2 {
            let coordinate = fixed[axis], domain = coverage.requestedDomains[surface * 2 + axis]
            let parameterDepth = max(retainedDepth,coordinate.inheritedDepth)
            guard parameterDepth <= maximumAlgebraicDepth,
                coordinate.inheritedCoefficientDepth <= maximumCoefficientDepth else {
                throw rationalAlgebraFailure("Exact SSI station cannot reset its retained scalar depths.")
            }
            var source = OriginalSourceScalarAdmission(base: admission, maximumDepth: maximumAlgebraicDepth,
                maximumCoefficientDepth: maximumCoefficientDepth, originalParameterDepth: coordinate.original.context.depth,
                originalCoefficientDepth: coordinate.original.context.coefficientDepth, inheritedParameterDepth: parameterDepth,
                inheritedCoefficientDepth: coordinate.inheritedCoefficientDepth, parameterDepth: parameterDepth,
                coefficientDepth: coordinate.inheritedCoefficientDepth)
            let available = try rationalAlgebraCount(coordinate.original.context.depth,maximumAlgebraicDepth - parameterDepth)
            do {
                if let lower = domain.lower {
                    let bound = try OriginalSingularFieldElement.constant(lower,in: coordinate.original.context,maximumDepth: available,usage: &source)
                    if try coordinate.original.subtracting(bound,maximumDepth: available,usage: &source).sign(maximumDepth: available,usage: &source) == .negative {
                        throw GeometryConversionError.invalidInput("Exact SSI fiber station is outside the original requested domain.")
                    }
                }
                if let upper = domain.upper {
                    let bound = try OriginalSingularFieldElement.constant(upper,in: coordinate.original.context,maximumDepth: available,usage: &source)
                    if try coordinate.original.subtracting(bound,maximumDepth: available,usage: &source).sign(maximumDepth: available,usage: &source) == .positive {
                        throw GeometryConversionError.invalidInput("Exact SSI fiber station is outside the original requested domain.")
                    }
                }
            } catch { admission = source.base; throw error }
            admission = source.base
        }
        let rational = try OriginalSingularFieldContext(usage: &admission)
        let sourcePolynomials: [ExactIntersectionPolynomial]?
        let sourcePredicate: OriginalPolynomialPredicate?
        let equationCount: Int, guardCount: Int
        let necessaryStart: Int, necessaryCount: Int
        switch coverage {
        case .single(let decomposition):
            let system = decomposition.system
            equationCount = system.equations.count; guardCount = system.denominatorGuards.count
            sourcePolynomials = nil; sourcePredicate = nil; necessaryStart = 0; necessaryCount = 0
        case .common(let proof):
            necessaryStart = proof.laws.count; necessaryCount = proof.necessaryIdeal.reducedBasis.count
            let sourceCapacity = try rationalAlgebraCount(necessaryStart, necessaryCount)
            try RationalAlgebraStorage.retain(sourceCapacity, of: ExactIntersectionPolynomial.self, usage: &admission)
            var commonLaws: [ExactIntersectionPolynomial] = []; commonLaws.reserveCapacity(sourceCapacity)
            try admission.consumeExactWork(sourceCapacity)
            commonLaws.append(contentsOf: proof.laws); commonLaws.append(contentsOf: proof.necessaryIdeal.reducedBasis)
            sourcePolynomials = commonLaws; sourcePredicate = proof.predicate; equationCount = 0; guardCount = 0
        }
        let sourceCount = try sourcePolynomials?.count ?? rationalAlgebraCount(equationCount, guardCount)
        let count = try rationalAlgebraCount(sourceCount, 2)
        try RationalAlgebraStorage.retain(count, of: OriginalOrderedIntersectionPolynomial.self, usage: &admission)
        var laws: [OriginalOrderedIntersectionPolynomial] = []; laws.reserveCapacity(count)
        for index in 0..<sourceCount {
            let polynomial: ExactIntersectionPolynomial
            if let sourcePolynomials { polynomial = sourcePolynomials[index] }
            else if case .single(let decomposition) = coverage {
                polynomial = index < equationCount ? decomposition.system.equations[index]
                    : decomposition.system.denominatorGuards[index - equationCount]
            } else { throw rationalAlgebraFailure("SSI ordered fiber lost its original source laws.") }
            let terms = try polynomial.orderedTerms(usage: &admission)
            try RationalAlgebraStorage.retain(terms.count, of: OriginalOrderedIntersectionPolynomial.Term.self, usage: &admission)
            var retained: [OriginalOrderedIntersectionPolynomial.Term] = []; retained.reserveCapacity(terms.count)
            for (power, coefficient) in terms {
                retained.append(.init(power: power,
                    coefficient: try .constant(coefficient, in: rational, maximumDepth: maximumAlgebraicDepth, usage: &admission),
                    inheritedParameterDepth: retainedDepth))
            }
            laws.append(try .init(variableCount: 4, terms: retained, maximumDepth: maximumAlgebraicDepth,
                maximumCoefficientDepth: maximumCoefficientDepth, inheritedParameterDepth: retainedDepth, usage: &admission))
        }
        for axis in 0..<2 {
            let coordinate = fixed[axis]
            try RationalAlgebraStorage.retain(2, of: OriginalOrderedIntersectionPolynomial.Term.self, usage: &admission)
            let terms: [OriginalOrderedIntersectionPolynomial.Term] = [
                .init(power: try .coordinate(at: surface * 2 + axis, variableCount: 4, usage: &admission),
                    coefficient: try .constant(.one, in: rational, maximumDepth: maximumAlgebraicDepth, usage: &admission),
                    inheritedParameterDepth: retainedDepth),
                .init(power: try .init((0,0,0,0,0),variableCount: 4), coefficient: coordinate.original,
                    inheritedParameterDepth: max(retainedDepth, coordinate.inheritedDepth),
                    inheritedCoefficientDepth: coordinate.inheritedCoefficientDepth)]
            // Negate the retained scalar in its source field without constructing a numerical substitute.
            try RationalAlgebraStorage.retain(2, of: OriginalOrderedIntersectionPolynomial.Term.self, usage: &admission)
            var station = terms
            var sourceAdmission = OriginalSourceScalarAdmission(base: admission, maximumDepth: maximumAlgebraicDepth,
                maximumCoefficientDepth: maximumCoefficientDepth, originalParameterDepth: coordinate.original.context.depth,
                originalCoefficientDepth: coordinate.original.context.coefficientDepth,
                inheritedParameterDepth: max(retainedDepth,coordinate.inheritedDepth),
                inheritedCoefficientDepth: coordinate.inheritedCoefficientDepth,
                parameterDepth: max(retainedDepth,coordinate.inheritedDepth), coefficientDepth: coordinate.inheritedCoefficientDepth)
            guard max(retainedDepth,coordinate.inheritedDepth) <= maximumAlgebraicDepth,
                coordinate.inheritedCoefficientDepth <= maximumCoefficientDepth else {
                throw rationalAlgebraFailure("Exact SSI station cannot reset its retained scalar depths.")
            }
            let available = try rationalAlgebraCount(coordinate.original.context.depth,
                maximumAlgebraicDepth - max(retainedDepth,coordinate.inheritedDepth))
            let negative: OriginalSingularFieldElement
            do { negative = try coordinate.original.negated(maximumDepth: available, usage: &sourceAdmission) }
            catch { admission = sourceAdmission.base; throw error }
            admission = sourceAdmission.base
            station[1] = .init(power: terms[1].power, coefficient: negative,
                inheritedParameterDepth: sourceAdmission.parameterDepth,
                inheritedCoefficientDepth: sourceAdmission.coefficientDepth)
            laws.append(try .init(variableCount: 4, terms: station, maximumDepth: maximumAlgebraicDepth,
                maximumCoefficientDepth: maximumCoefficientDepth, inheritedParameterDepth: retainedDepth, usage: &admission))
        }
        let instructionCount = try rationalAlgebraCount(sourcePredicate?.original.instructions.count
            ?? rationalAlgebraCount(1, rationalAlgebraCount(rationalAlgebraCount(sourceCount, 2, multiply: true), guardCount)),
            rationalAlgebraCount(coverage.effectiveDomains == nil ? 6 : 4, rationalAlgebraCount(necessaryCount, 2, multiply: true)))
        try RationalAlgebraStorage.retain(instructionCount, of: OriginalPolynomialPredicate.Instruction.self, usage: &admission)
        var instructions: [OriginalPolynomialPredicate.Instruction] = []; instructions.reserveCapacity(instructionCount)
        if let sourcePredicate {
            for instruction in sourcePredicate.original.instructions {
                try intersectionAlgebraStep(&admission)
                switch instruction {
                case .literal(let value): instructions.append(.literal(value))
                case .atom(let index, let sign):
                    let original: OriginalPolynomialPredicate.Sign
                    switch sign { case .negative: original = .negative; case .zero: original = .zero; case .positive: original = .positive }
                    instructions.append(.sign(polynomial: index, original))
                case .not: instructions.append(.not)
                case .and: instructions.append(.and)
                case .or: instructions.append(.or)
                }
            }
        } else {
            instructions.append(.literal(true))
            for ordinal in 0..<sourceCount {
                instructions.append(.sign(polynomial: ordinal, .zero))
                if ordinal >= equationCount { instructions.append(.not) }
                instructions.append(.and)
            }
        }
        for ordinal in necessaryStart..<(necessaryStart + necessaryCount) {
            try admission.consumeExactWork(2)
            instructions.append(.sign(polynomial: ordinal, .zero)); instructions.append(.and)
        }
        for ordinal in sourceCount..<count { instructions.append(.sign(polynomial: ordinal, .zero)); instructions.append(.and) }
        if coverage.effectiveDomains == nil { instructions.append(.literal(false)); instructions.append(.and) }
        let predicate = try OriginalPolynomialPredicate(polynomialCount: laws.count,instructions: instructions,usage: &admission)
        try RationalAlgebraStorage.retain(laws.count, of: OriginalOrderedPolynomial.self, usage: &admission)
        var published: [OriginalOrderedPolynomial] = []; published.reserveCapacity(laws.count)
        for law in laws { published.append(.init(original: law)) }
        let original = try OriginalPolynomialRelation(variableCount: 4, orderedPolynomials: published,
            predicate: predicate, domains: coverage.effectiveDomains ?? coverage.nativeDomains, usage: &admission)
        let ordered = try OriginalOrderedIntersectionCells.prepare(polynomials: laws, predicate: predicate.original,
            variableCount: 4, domains: original.domains, maximumDepth: maximumAlgebraicDepth,
            maximumCoefficientDepth: maximumCoefficientDepth, usage: &admission)
        let incidence = try OriginalRationalIntersectionIncidence.prepare(partition: ordered.partition,
            maximumDepth: maximumAlgebraicDepth, usage: &admission)
        let relation = try OriginalRealRelation(original: original, ordered: ordered, incidence: incidence,
            components: incidence.connectedComponents(usage: &admission), maximumDepth: maximumAlgebraicDepth, usage: &admission)
        try RationalAlgebraStorage.retain(1,of: OriginalNativeSurfaceSurfaceFiber.self,usage: &admission)
        try CurrentTaskCancellationChecker().checkCancellation()
        return .init(source: self,surfaceRole: surface,u: u,v: v,relation: relation)
    }
}
