import CADCore

extension OriginalNativeCurveSurfaceRelation {
    /// Every UV cell over the exact station, including multiple preimages and collapsed fibers.
    /// The returned relation retains this station's original field and causal depths.
    public func surfaceParameterFiber<A: ExactScalarAdmission & ~Copyable>(at station: OriginalAlgebraicCoordinate,
        maximumDepth: Int, maximumCoefficientDepth: Int,
        usage: inout A) throws -> OriginalRealRelation {
        guard maximumDepth >= 0, (0...32).contains(maximumCoefficientDepth),
            station.inheritedDepth <= maximumDepth,
            station.inheritedCoefficientDepth <= maximumCoefficientDepth else {
            throw rationalAlgebraFailure("Native fiber cannot reset its exact station admission depths.")
        }
        let context = station.original.context
        let composed = try intersectionSourceCalculation(originalParameterDepth: context.depth,
            originalCoefficientDepth: context.coefficientDepth,
            inheritedParameterDepth: station.inheritedDepth,
            inheritedCoefficientDepth: station.inheritedCoefficientDepth,
            maximumDepth: maximumDepth, maximumCoefficientDepth: maximumCoefficientDepth,
            usage: &usage) { admission in
        let available = try rationalAlgebraCount(context.depth, maximumDepth - station.inheritedDepth)
        try intersectionAlgebraStep(&admission)
        var included = effectiveDomains != nil
        if let domains = effectiveDomains {
            for (bound, lower) in [(domains[0].lower, true), (domains[0].upper, false)] {
                if let bound {
                    let exact = try OriginalSingularFieldElement.constant(bound, in: context,
                        maximumDepth: available, usage: &admission)
                    let difference = try lower
                        ? station.original.subtracting(exact, maximumDepth: available, usage: &admission)
                        : exact.subtracting(station.original, maximumDepth: available, usage: &admission)
                    if try difference.sign(maximumDepth: available, usage: &admission) == .negative { included = false }
                }
            }
        }
        let system = charts[0].system
        let lawCount = try composition?.laws.count ?? rationalAlgebraCount(system.equations.count, system.denominatorGuards.count)
        try RationalAlgebraStorage.retain(lawCount, of: OriginalOrderedPolynomial.self, usage: &admission)
        var laws: [OriginalOrderedPolynomial] = []; laws.reserveCapacity(lawCount)
        func substituted(_ polynomial: ExactIntersectionPolynomial) throws -> OriginalOrderedPolynomial {
            let originalTerms = try polynomial.orderedTerms(usage: &admission)
            try RationalAlgebraStorage.retain(originalTerms.count,
                of: OriginalOrderedIntersectionPolynomial.Term.self, usage: &admission)
            var terms: [OriginalOrderedIntersectionPolynomial.Term] = []; terms.reserveCapacity(originalTerms.count)
            for (power, coefficient) in originalTerms {
                try intersectionAlgebraStep(&admission)
                var scalar = try OriginalSingularFieldElement.constant(coefficient, in: context,
                    maximumDepth: available, usage: &admission)
                let degree = try power.exponent(at: 0)
                for _ in 0..<degree {
                    scalar = try scalar.multiplied(by: station.original, maximumDepth: available, usage: &admission)
                }
                let uv = try ExactIntersectionPolynomial.Power((power.b, power.c, 0, 0, 0), variableCount: 2)
                terms.append(.init(power: uv, coefficient: scalar,
                    inheritedParameterDepth: (try admission.depth).value,
                    inheritedCoefficientDepth: (try admission.depth).coefficient))
            }
            return try .init(original: .init(variableCount: 2, terms: terms,
                maximumDepth: maximumDepth, maximumCoefficientDepth: maximumCoefficientDepth, usage: &admission))
        }
        let predicate: OriginalPolynomialPredicate
        if let composition {
            for law in composition.laws { laws.append(try substituted(law)) }
            // Substitution preserves each indexed original sign atom and chart-owner branch.
            let instructionCount = try rationalAlgebraCount(composition.predicate.original.instructions.count, 2)
            try RationalAlgebraStorage.retain(instructionCount,
                of: OriginalPolynomialPredicate.Instruction.self, usage: &admission)
            var instructions: [OriginalPolynomialPredicate.Instruction] = []
            instructions.reserveCapacity(instructionCount)
            for instruction in composition.predicate.original.instructions {
                try intersectionAlgebraStep(&admission)
                switch instruction {
                case .literal(let value): instructions.append(.literal(value))
                case .atom(let index, let sign):
                    let publicSign: OriginalPolynomialPredicate.Sign
                    switch sign { case .negative: publicSign = .negative; case .zero: publicSign = .zero; case .positive: publicSign = .positive }
                    instructions.append(.sign(polynomial: index, publicSign))
                case .not: instructions.append(.not)
                case .and: instructions.append(.and)
                case .or: instructions.append(.or)
                }
            }
            instructions.append(.literal(included)); instructions.append(.and)
            predicate = try .init(polynomialCount: lawCount, instructions: instructions, usage: &admission)
        } else {
            for law in system.equations { laws.append(try substituted(law)) }
            for guardLaw in system.denominatorGuards { laws.append(try substituted(guardLaw)) }
            let instructionCount = try rationalAlgebraCount(1,
                rationalAlgebraCount(rationalAlgebraCount(system.equations.count, 2, multiply: true),
                    rationalAlgebraCount(system.denominatorGuards.count, 3, multiply: true)))
            try RationalAlgebraStorage.retain(instructionCount,
                of: OriginalPolynomialPredicate.Instruction.self, usage: &admission)
            var instructions: [OriginalPolynomialPredicate.Instruction] = []
            instructions.reserveCapacity(instructionCount); instructions.append(.literal(included))
            for index in 0..<lawCount {
                try intersectionAlgebraStep(&admission)
                instructions.append(.sign(polynomial: index, .zero))
                if index >= system.equations.count { instructions.append(.not) }
                instructions.append(.and)
            }
            predicate = try OriginalPolynomialPredicate(polynomialCount: lawCount,
                instructions: instructions, usage: &admission)
        }
        try RationalAlgebraStorage.retain(2, of: OriginalRationalParameterDomain.self, usage: &admission)
        let domains = Array((effectiveDomains ?? requestedDomains)[1...2])
        let relation = try OriginalPolynomialRelation(variableCount: 2, orderedPolynomials: laws,
            predicate: predicate, domains: domains, usage: &admission)
        return relation
        }
        return try DefaultOriginalPolynomialRelationResolver().decompose(composed.value,
            maximumDepth: maximumDepth, maximumCoefficientDepth: maximumCoefficientDepth, usage: &usage)
    }
}
