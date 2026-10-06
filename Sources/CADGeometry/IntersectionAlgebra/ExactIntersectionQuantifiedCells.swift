import CADCore

/// Whole-cell quantified truth with retained original witness or complete child proofs.
package struct ExactIntersectionQuantifiedCells: Sendable {
    package enum Quantifier: Sendable { case exists, forall }
    package struct Truth: Sendable {
        package let cellIndex: Int
        package let value: Bool
        package let decisionIndex: Int?
    }
    package struct Child: Sendable {
        package let kind: OriginalRationalIntersectionCells.Kind
        package let context: OriginalSingularFieldContext
        package let coordinates: [OriginalSingularFieldElement]
        package let signs: [ExactAlgebraicRealRoot.Sign?]
        package let decisionIndex: Int?
        package let value: Bool
    }
    package struct Decision: Sendable {
        package let axis: Int
        package let quantifier: Quantifier
        package let context: OriginalSingularFieldContext
        package let coordinates: [OriginalSingularFieldElement]
        package let roots: [OriginalSingularFieldRoot]
        package let knownSigns: [ExactAlgebraicRealRoot.Sign?]
        package var constantSigns: [ExactAlgebraicRealRoot.Sign?]? { totalChildCount == 0 ? knownSigns : nil }
        package let totalChildCount: Int
        package let zeroGuardIndex: Int?
        package let children: [Child]
        package let value: Bool
    }
    package let tower: ExactIntersectionProjectionTower
    package let program: ExactIntersectionBooleanProgram
    package let quantifiers: [Quantifier]
    package let freeDomainEquations: [ExactIntersectionPolynomial]
    package let freeVariableCount: Int
    package let freePartition: OriginalRationalIntersectionCells?
    package let freeCells: [Truth]
    package let decisions: [Decision]
    package let closedTruth: Bool?
    package let coefficientVariableCount: Int
    package let maximumCoefficientDepth: Int

    private init(tower: ExactIntersectionProjectionTower, program: ExactIntersectionBooleanProgram,
        quantifiers: [Quantifier], freeDomainEquations: [ExactIntersectionPolynomial], freeVariableCount: Int, freePartition: OriginalRationalIntersectionCells?,
        freeCells: [Truth], decisions: [Decision], closedTruth: Bool?,
        coefficientVariableCount: Int, maximumCoefficientDepth: Int) {
        self.tower = tower; self.program = program; self.quantifiers = quantifiers; self.freeDomainEquations = freeDomainEquations
        self.freeVariableCount = freeVariableCount; self.freePartition = freePartition
        self.freeCells = freeCells; self.decisions = decisions; self.closedTruth = closedTruth
        self.coefficientVariableCount = coefficientVariableCount; self.maximumCoefficientDepth = maximumCoefficientDepth
    }

    package static func prepare<B: RationalAlgebraAdmitting>(polynomials: [ExactIntersectionPolynomial],
        program: ExactIntersectionBooleanProgram, variableCount: Int, freeVariableCount: Int,
        quantifiers: [Quantifier], freeDomainEquations: [ExactIntersectionPolynomial] = [],
        freeDomains: [OriginalRationalParameterDomain]? = nil,
        coefficientVariableCount: Int = 0, maximumCoefficientDepth: Int = 0,
        inheritedParameterDepth: Int = 0, inheritedCoefficientDepth: Int = 0,
        maximumDepth: Int, usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        guard (1...ExactIntersectionPolynomial.maximumVariableCount).contains(variableCount),
            freeVariableCount >= 0, freeVariableCount <= variableCount, maximumDepth >= 0,
            quantifiers.count == variableCount - freeVariableCount,
            program.polynomialCount == polynomials.count,
            freeVariableCount > 0 || freeDomainEquations.isEmpty,
            freeDomains == nil || freeDomains?.count == freeVariableCount,
            coefficientVariableCount >= 0, coefficientVariableCount <= freeVariableCount,
            (0...32).contains(maximumCoefficientDepth), inheritedParameterDepth >= 0, inheritedParameterDepth <= maximumDepth,
            inheritedCoefficientDepth >= 0, inheritedCoefficientDepth <= maximumCoefficientDepth else {
            throw rationalAlgebraFailure("Quantified truth requires one bound free prefix and quantified suffix.")
        }
        for equation in freeDomainEquations {
            try intersectionAlgebraStep(&usage)
            guard equation.variableCount == freeVariableCount else {
                throw rationalAlgebraFailure("Free-domain constraints must belong to the original free prefix ring.")
            }
        }
        let tower = try ExactIntersectionProjectionTower.prepare(sources: polynomials,
            variableCount: variableCount, usage: &usage)
        try RationalAlgebraStorage.retain(program.maximumStackCount, of: Bool.self, usage: &usage)
        var scratch: [Bool] = []; scratch.reserveCapacity(program.maximumStackCount)
        try RationalAlgebraStorage.retain(program.maximumStackCount, of: Bool?.self, usage: &usage)
        var partialScratch: [Bool?] = []; partialScratch.reserveCapacity(program.maximumStackCount)
        var decisions: [Decision] = [], free: [Truth] = []
        let prefix: OriginalRationalIntersectionCells?
        let closed: Bool?
        if freeVariableCount == 0 {
            let context = try OriginalSingularFieldContext(usage: &usage)
            let proof = try decide(axis: 0, context: context, coordinates: [], inheritedDepth: inheritedParameterDepth,
                tower: tower, program: program, inheritedSigns: nil, freeVariableCount: 0, quantifiers: quantifiers,
                maximumDepth: maximumDepth, scratch: &scratch, partialScratch: &partialScratch, decisions: &decisions, usage: &usage)
            closed = decisions[proof].value; prefix = nil
        } else {
            let sources = tower.levels[variableCount - freeVariableCount].sources
            try RationalAlgebraStorage.retain(sources.count, of: ExactIntersectionPolynomial.self, usage: &usage)
            var projected: [ExactIntersectionPolynomial] = []; projected.reserveCapacity(sources.count)
            for source in sources { projected.append(try source.lowered(to: freeVariableCount, usage: &usage)) }
            try RationalAlgebraStorage.retain(freeVariableCount, of: ScalarInterval?.self, usage: &usage)
            try RationalAlgebraStorage.retain(try rationalAlgebraCount(freeDomainEquations.count, projected.count),
                of: ExactIntersectionPolynomial.self, usage: &usage)
            var retainedSources = freeDomainEquations
            if let freeDomains {
                for (axis, domain) in freeDomains.enumerated() {
                    let coordinate = try ExactIntersectionPolynomial.coordinate(variableCount: freeVariableCount, at: axis, usage: &usage)
                    for endpoint in [domain.lower, domain.upper] {
                        guard let endpoint else { continue }
                        try RationalAlgebraStorage.retain(1, of: ExactIntersectionPolynomial.self, usage: &usage)
                        retainedSources.append(try coordinate.subtracting(.constant(variableCount: freeVariableCount,
                            value: endpoint, usage: &usage), usage: &usage))
                    }
                }
            }
            retainedSources += projected
            let retainedProjection = try tower.retainedPrefix(variableCount: freeVariableCount,
                sources: retainedSources, usage: &usage)
            let partition = try OriginalRationalIntersectionCells.prepare(equations: freeDomainEquations, variableCount: freeVariableCount,
                exactDomains: freeDomains ?? Array(repeating: OriginalRationalParameterDomain(lower: nil, upper: nil, usage: &usage), count: freeVariableCount), partitionPolynomials: projected, pruneExcludedPrefixes: !freeDomainEquations.isEmpty,
                coefficientVariableCount: coefficientVariableCount, maximumCoefficientDepth: maximumCoefficientDepth,
                inheritedParameterDepth: inheritedParameterDepth, inheritedCoefficientDepth: inheritedCoefficientDepth,
                preparedProjectionTower: retainedProjection, pruneDomainPrefixes: freeDomains != nil, maximumDepth: maximumDepth, usage: &usage)
            for index in partition.solutionCells {
                try intersectionAlgebraStep(&usage)
                let cell = partition.cells[index]
                let decision: Int?, value: Bool
                if freeVariableCount == variableCount {
                    decision = nil
                    try RationalAlgebraStorage.retain(polynomials.count, of: ExactAlgebraicRealRoot.Sign.self, usage: &usage)
                    var signs: [ExactAlgebraicRealRoot.Sign] = []; signs.reserveCapacity(polynomials.count)
                    for polynomial in polynomials {
                        signs.append(try OriginalIntersectionFieldEvaluation.evaluated(polynomial, context: cell.context,
                            coordinates: cell.coordinates, maximumDepth: maximumDepth, usage: &usage)
                            .sign(maximumDepth: maximumDepth, usage: &usage))
                    }
                    value = try program.evaluate(signs: signs, scratch: &scratch, usage: &usage)
                } else {
                    decision = try decide(axis: freeVariableCount, context: cell.context, coordinates: cell.coordinates,
                        inheritedDepth: cell.admissionDepth, tower: tower, program: program,
                        inheritedSigns: nil, freeVariableCount: freeVariableCount, quantifiers: quantifiers, maximumDepth: maximumDepth,
                        scratch: &scratch, partialScratch: &partialScratch, decisions: &decisions, usage: &usage)
                    guard let proof = decision else { throw rationalAlgebraFailure("A free cell lost quantified proof.") }
                    value = decisions[proof].value
                }
                try RationalAlgebraStorage.retain(1, of: Truth.self, usage: &usage)
                free.append(Truth(cellIndex: index, value: value, decisionIndex: decision))
            }
            prefix = partition; closed = nil
        }
        try RationalAlgebraStorage.retain(quantifiers.count, of: Quantifier.self, usage: &usage)
        try RationalAlgebraStorage.retain(freeDomainEquations.count, of: ExactIntersectionPolynomial.self, usage: &usage)
        return Self(tower: tower, program: program, quantifiers: quantifiers, freeDomainEquations: freeDomainEquations,
            freeVariableCount: freeVariableCount, freePartition: prefix, freeCells: free,
            decisions: decisions, closedTruth: closed, coefficientVariableCount: coefficientVariableCount,
            maximumCoefficientDepth: maximumCoefficientDepth)
    }

    /// Original atom signs needed to prove the whole leaf formula; omitted signs remain unknown.
    package static func evaluateLeaf<B: RationalAlgebraAdmitting>(polynomials: [ExactIntersectionPolynomial],
        program: ExactIntersectionBooleanProgram, context: OriginalSingularFieldContext,
        coordinates: [OriginalSingularFieldElement], inheritedSigns: [ExactAlgebraicRealRoot.Sign?],
        maximumDepth: Int, scratch: inout [Bool?], usage: inout B) throws
        -> (signs: [ExactAlgebraicRealRoot.Sign?], value: Bool) {
        try intersectionAlgebraStep(&usage)
        guard polynomials.count == program.polynomialCount, inheritedSigns.count == program.polynomialCount else {
            throw rationalAlgebraFailure("A quantified leaf lost its original atom bindings.")
        }
        try RationalAlgebraStorage.retain(inheritedSigns.count, of: ExactAlgebraicRealRoot.Sign?.self, usage: &usage)
        var signs = inheritedSigns
        var truth = try program.partialValue(signs: signs, scratch: &scratch, usage: &usage)
        for instruction in program.instructions {
            if truth != nil { break }
            try intersectionAlgebraStep(&usage)
            guard case .atom(let index, _) = instruction, signs[index] == nil else { continue }
            signs[index] = try OriginalIntersectionFieldEvaluation.evaluated(polynomials[index], context: context,
                coordinates: coordinates, maximumDepth: maximumDepth, usage: &usage)
                .sign(maximumDepth: maximumDepth, usage: &usage)
            truth = try program.partialValue(signs: signs, scratch: &scratch, usage: &usage)
        }
        guard let truth else { throw rationalAlgebraFailure("A quantified leaf has no complete Boolean consequence.") }
        try CurrentTaskCancellationChecker().checkCancellation()
        return (signs, truth)
    }

    private static func decide<B: RationalAlgebraAdmitting>(axis: Int,
        context: OriginalSingularFieldContext, coordinates: [OriginalSingularFieldElement], inheritedDepth: Int,
        tower: ExactIntersectionProjectionTower, program: ExactIntersectionBooleanProgram,
        inheritedSigns: [ExactAlgebraicRealRoot.Sign?]?,
        freeVariableCount: Int, quantifiers: [Quantifier], maximumDepth: Int, scratch: inout [Bool], partialScratch: inout [Bool?],
        decisions: inout [Decision], usage: inout B) throws -> Int {
        try intersectionAlgebraStep(&usage)
        guard coordinates.count == axis, axis >= freeVariableCount, axis < tower.variableCount else {
            throw rationalAlgebraFailure("Quantified traversal lost its original coordinate prefix.")
        }
        let quantifier = quantifiers[axis - freeVariableCount]
        let original = tower.levels[0].sources
        try RationalAlgebraStorage.retain(program.polynomialCount, of: ExactAlgebraicRealRoot.Sign?.self, usage: &usage)
        try RationalAlgebraStorage.retain(program.polynomialCount, of: Bool.self, usage: &usage)
        if let inheritedSigns, inheritedSigns.count != program.polynomialCount {
            throw rationalAlgebraFailure("Quantified descent lost its bound original prefix signs.")
        }
        var known: [ExactAlgebraicRealRoot.Sign?] = inheritedSigns ?? Array(repeating: nil, count: program.polynomialCount)
        var visited = Array(repeating: false, count: program.polynomialCount)
        var constantTruth = try program.partialValue(signs: known, scratch: &partialScratch, usage: &usage)
        var zeroGuard: (index: Int, polynomial: OriginalSingularFieldPolynomial)?
        for instruction in program.instructions {
            if constantTruth != nil { break }
            try intersectionAlgebraStep(&usage)
            guard case .atom(let index, _) = instruction, known[index] == nil, !visited[index] else { continue }
            visited[index] = true
            guard let polynomial = try OriginalIntersectionFieldEvaluation.specialized(original[index], at: axis,
                context: context, coordinates: coordinates, maximumDepth: maximumDepth, usage: &usage) else { continue }
            if polynomial.isZero { known[index] = .zero }
            else if polynomial.degree == 0 {
                known[index] = try polynomial.coefficients[0].sign(maximumDepth: maximumDepth, usage: &usage)
            } else if zeroGuard == nil, case .exists = quantifier {
                try RationalAlgebraStorage.retain(known.count, of: ExactAlgebraicRealRoot.Sign?.self, usage: &usage)
                var proposal = known
                proposal[index] = .positive
                if try program.partialValue(signs: proposal, scratch: &partialScratch, usage: &usage) == false {
                    proposal[index] = .negative
                    if try program.partialValue(signs: proposal, scratch: &partialScratch, usage: &usage) == false {
                        zeroGuard = (index, polynomial)
                    }
                }
            }
            if known[index] != nil {
                constantTruth = try program.partialValue(signs: known, scratch: &partialScratch, usage: &usage)
            }
        }
        if let truth = constantTruth {
            try RationalAlgebraStorage.retain(1, of: Decision.self, usage: &usage)
            let index = decisions.count
            decisions.append(Decision(axis: axis, quantifier: quantifier, context: context,
                coordinates: coordinates, roots: [], knownSigns: known,
                totalChildCount: 0, zeroGuardIndex: nil, children: [], value: truth))
            return index
        }
        let level = tower.levels[tower.variableCount - 1 - axis]
        let rootSources: [OriginalSingularFieldPolynomial]
        if let zeroGuard {
            try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldPolynomial.self, usage: &usage)
            rootSources = [zeroGuard.polynomial]
        } else {
            try RationalAlgebraStorage.retain(level.sources.count, of: OriginalSingularFieldPolynomial.self, usage: &usage)
            var specialized: [OriginalSingularFieldPolynomial] = []; specialized.reserveCapacity(level.sources.count)
            for source in level.sources {
                guard let polynomial = try OriginalIntersectionFieldEvaluation.specialized(source, at: axis,
                    context: context, coordinates: coordinates, maximumDepth: maximumDepth, usage: &usage) else {
                    throw rationalAlgebraFailure("An original quantifier level contains a later coordinate.")
                }
                specialized.append(polynomial)
            }
            rootSources = specialized
        }
        var roots = try OriginalRationalIntersectionCells.completeRootUnion(sources: rootSources,
            inheritedDepth: max(inheritedDepth, context.depth), maximumDepth: maximumDepth, usage: &usage)
        try OriginalRationalIntersectionCells.separate(&roots, maximumDepth: maximumDepth, usage: &usage)
        let total = try rationalAlgebraCount(rationalAlgebraCount(roots.count, 2, multiply: true), 1)
        var reduced: Bool
        switch quantifier { case .exists: reduced = false; case .forall: reduced = true }
        var children: [Child] = []
        let visitedCount = zeroGuard == nil ? total : roots.count
        for visit in 0..<visitedCount {
            try intersectionAlgebraStep(&usage)
            let ordinal = zeroGuard == nil ? visit : visit * 2 + 1
            let position = ordinal / 2
            let kind: OriginalRationalIntersectionCells.Kind
            let value: OriginalSingularFieldElement
            var depth = inheritedDepth
            if ordinal % 2 == 0 {
                kind = .sector(lowerOrdinal: position > 0 ? position - 1 : nil,
                    upperOrdinal: position < roots.count ? position : nil)
                if position > 0 { depth = max(depth, roots[position - 1].isolation.depth) }
                if position < roots.count { depth = max(depth, roots[position].isolation.depth) }
                value = try .constant(OriginalRationalIntersectionCells.sectorSample(roots: roots,
                    position: position, usage: &usage), in: context, maximumDepth: maximumDepth, usage: &usage)
            } else {
                kind = .section(rootOrdinal: position)
                let root = try OriginalRationalIntersectionCells.minimalSectionRoot(roots[position], sources: rootSources,
                    maximumDepth: maximumDepth, usage: &usage)
                depth = max(depth, root.isolation.depth)
                if root.polynomial.degree == 1 {
                    value = try root.polynomial.coefficients[0].negated(maximumDepth: maximumDepth, usage: &usage)
                        .divided(by: root.polynomial.coefficients[1], maximumDepth: maximumDepth, usage: &usage)
                } else { value = try root.value(maximumDepth: maximumDepth, usage: &usage) }
            }
            depth = max(depth, value.context.depth)
            guard depth <= maximumDepth else { throw rationalAlgebraFailure("Quantified truth cannot reset inherited root depth.") }
            try usage.visitExactCell(depth: depth)
            try RationalAlgebraStorage.retain(axis + 1, of: OriginalSingularFieldElement.self, usage: &usage)
            var tuple: [OriginalSingularFieldElement] = []; tuple.reserveCapacity(axis + 1)
            for coordinate in coordinates {
                tuple.append(try coordinate.embedded(in: value.context, maximumDepth: maximumDepth, usage: &usage))
            }
            tuple.append(value)
            let childProof: Int?, truth: Bool
            var signs: [ExactAlgebraicRealRoot.Sign?] = []
            if axis + 1 == tower.variableCount {
                let leaf = try evaluateLeaf(polynomials: original, program: program, context: value.context,
                    coordinates: tuple, inheritedSigns: known, maximumDepth: maximumDepth,
                    scratch: &partialScratch, usage: &usage)
                signs = leaf.signs
                childProof = nil; truth = leaf.value
            } else {
                childProof = try decide(axis: axis + 1, context: value.context, coordinates: tuple,
                    inheritedDepth: depth, tower: tower, program: program, inheritedSigns: known, freeVariableCount: freeVariableCount,
                    quantifiers: quantifiers, maximumDepth: maximumDepth, scratch: &scratch, partialScratch: &partialScratch, decisions: &decisions, usage: &usage)
                guard let proof = childProof else { throw rationalAlgebraFailure("A quantified child lost its original proof.") }
                truth = decisions[proof].value
            }
            try RationalAlgebraStorage.retain(1, of: Child.self, usage: &usage)
            children.append(Child(kind: kind, context: value.context, coordinates: tuple,
                signs: signs, decisionIndex: childProof, value: truth))
            switch quantifier {
            case .exists: reduced = reduced || truth; if truth { break }
            case .forall: reduced = reduced && truth; if !truth { break }
            }
        }
        // An existential witness or universal counterexample is a whole-cell
        // decision by the retained projection. A necessary zero guard excludes its
        // whole complement; otherwise absence/truth requires every original child.
        switch quantifier {
        case .exists:
            guard reduced || children.count == visitedCount else { throw rationalAlgebraFailure("Existential absence omitted an original cell.") }
        case .forall:
            guard !reduced || children.count == total else { throw rationalAlgebraFailure("Universal truth omitted an original cell.") }
        }
        try RationalAlgebraStorage.retain(1, of: Decision.self, usage: &usage)
        let index = decisions.count
        decisions.append(Decision(axis: axis, quantifier: quantifier, context: context,
            coordinates: coordinates, roots: roots, knownSigns: known, totalChildCount: total,
            zeroGuardIndex: zeroGuard?.index, children: children, value: reduced))
        return index
    }
}
