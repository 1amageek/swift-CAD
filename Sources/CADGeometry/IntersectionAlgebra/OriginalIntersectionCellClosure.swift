import CADCore

/// Exact closure of one original cell, retaining a complete refined free-space cover.
package struct OriginalIntersectionCellClosure: Sendable {
    package enum Proof: Sendable {
        case point
        case finiteBranch(OriginalFiniteBranchClosure)
        case affineCell(OriginalAffineCellClosure)
        case quantified(ExactIntersectionQuantifiedCells)
    }
    package let source: OriginalIntersectionCellCondition
    package let proof: Proof
    package let freePartition: OriginalRationalIntersectionCells
    package let includedCells: [Int]
    package let originalPredicates: [ExactIntersectionPolynomial]
    package let predicateIdeal: ExactIntersectionIdeal?
    package let candidateCoordinateMap: [Int]?
    package let freeSupportReduction: OriginalPositiveGuardPolynomialReduction?
    package let predicateReduction: OriginalPositiveGuardPolynomialReduction?

    private init(source: OriginalIntersectionCellCondition, proof: Proof,
        freePartition: OriginalRationalIntersectionCells, includedCells: [Int],
        originalPredicates: [ExactIntersectionPolynomial], predicateIdeal: ExactIntersectionIdeal?,
        candidateCoordinateMap: [Int]? = nil,
        predicateReduction: OriginalPositiveGuardPolynomialReduction? = nil,
        freeSupportReduction: OriginalPositiveGuardPolynomialReduction? = nil) {
        self.source = source; self.proof = proof
        self.freePartition = freePartition; self.includedCells = includedCells
        self.originalPredicates = originalPredicates; self.predicateIdeal = predicateIdeal
        self.candidateCoordinateMap = candidateCoordinateMap; self.predicateReduction = predicateReduction
        self.freeSupportReduction = freeSupportReduction
    }

    package static func prepare<B: ExactScalarAdmission & ~Copyable>(partition: OriginalRationalIntersectionCells,
        cellIndex: Int, allowAffineProofs: Bool = true, allowFiniteBranchProofs: Bool = true,
        maximumDepth: Int, usage: inout B) throws -> Self {
        let source = try OriginalIntersectionCellCondition(partition: partition, cellIndex: cellIndex, usage: &usage)
        let count = source.variableCount
        guard count > 0 else {
            throw rationalAlgebraFailure("Original closure requires a positive original parameter count.")
        }
        guard maximumDepth >= 0, partition.cells[cellIndex].admissionDepth <= maximumDepth else {
            throw rationalAlgebraFailure("Original closure cannot reset its issued source-cell depth.")
        }
        let coefficientCount = source.coefficientVariableCount
        guard coefficientCount == 0 || source.fixedCoefficientCellIndex != nil else {
            throw rationalAlgebraFailure("Ordered closure requires one issued fixed coefficient-prefix point.")
        }
        if partition.cells[cellIndex].dimension == 0 {
            try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
            return Self(source: source, proof: .point, freePartition: partition, includedCells: [cellIndex],
                originalPredicates: source.polynomials, predicateIdeal: nil)
        }
        if allowFiniteBranchProofs, let monic = try OriginalFiniteBranchClosure.prepare(partition: partition,
            cellIndex: cellIndex, maximumDepth: maximumDepth, usage: &usage) {
            return Self(source: source, proof: .finiteBranch(monic), freePartition: partition, includedCells: monic.includedCells,
                originalPredicates: source.polynomials, predicateIdeal: nil)
        }
        if allowAffineProofs, let affine = try OriginalAffineCellClosure.prepare(partition: partition,
            source: source, maximumDepth: maximumDepth, usage: &usage) {
            return Self(source: source, proof: .affineCell(affine), freePartition: partition,
                includedCells: affine.includedCells, originalPredicates: source.polynomials, predicateIdeal: nil)
        }
        var closedSupport: [ExactIntersectionPolynomial] = []
        for (index, polynomial) in source.polynomials.enumerated() {
            try intersectionAlgebraStep(&usage)
            if source.signs[index] == .zero && !polynomial.isZero {
                try RationalAlgebraStorage.retain(1, of: ExactIntersectionPolynomial.self, usage: &usage)
                closedSupport.append(polynomial)
            }
        }
        try RationalAlgebraStorage.retain(count - coefficientCount, of: Int.self, usage: &usage)
        var mobile: [Int] = []; mobile.reserveCapacity(count - coefficientCount)
        try RationalAlgebraStorage.retain(count, of: Int.self, usage: &usage)
        var candidates: [Int] = []; candidates.reserveCapacity(count)
        for axis in 0..<count {
            try intersectionAlgebraStep(&usage)
            if try axis < coefficientCount || isFixedOriginalCoordinate(axis, source: source, usage: &usage) {
                candidates.append(axis)
            } else {
                candidates.append(try rationalAlgebraCount(try rationalAlgebraCount(count, 1), mobile.count))
                mobile.append(axis)
            }
        }
        let geometryCount = mobile.count
        var variables = try rationalAlgebraCount(try rationalAlgebraCount(count, geometryCount), 1)
        try RationalAlgebraStorage.retain(count, of: Int.self, usage: &usage)
        let free = Array(0..<count)
        var polynomials: [ExactIntersectionPolynomial] = []
        for polynomial in source.polynomials {
            try intersectionAlgebraStep(&usage)
            try RationalAlgebraStorage.retain(1, of: ExactIntersectionPolynomial.self, usage: &usage)
            polynomials.append(try polynomial.remapped(to: variables, coordinates: candidates, usage: &usage))
        }
        let radius = try ExactIntersectionPolynomial.coordinate(variableCount: variables, at: count, usage: &usage)
        let radiusIndex = polynomials.count
        try RationalAlgebraStorage.retain(1, of: ExactIntersectionPolynomial.self, usage: &usage)
        polynomials.append(radius)
        let boxIndex = polynomials.count
        for axis in mobile {
            try intersectionAlgebraStep(&usage)
            let p = try ExactIntersectionPolynomial.coordinate(variableCount: variables, at: axis, usage: &usage)
            let q = try ExactIntersectionPolynomial.coordinate(variableCount: variables,
                at: candidates[axis], usage: &usage)
            let difference = try p.subtracting(q, usage: &usage)
            try RationalAlgebraStorage.retain(2, of: ExactIntersectionPolynomial.self, usage: &usage)
            polynomials.append(try radius.subtracting(difference, usage: &usage))
            polynomials.append(try radius.adding(difference, usage: &usage))
        }
        // Retain the original guards. Normal forms are equivalent only while
        // those guards hold; replacing a guard by zero would erase membership.
        try RationalAlgebraStorage.retain(polynomials.count, of: ExactIntersectionPolynomial.self, usage: &usage)
        let originalPredicates = polynomials
        var guardEquations: [ExactIntersectionPolynomial] = []
        for (index, polynomial) in source.polynomials.enumerated() {
            try intersectionAlgebraStep(&usage)
            if source.signs[index] != .zero || polynomial.isZero { continue }
            try RationalAlgebraStorage.retain(2, of: ExactIntersectionPolynomial.self, usage: &usage)
            guardEquations.append(try polynomial.remapped(to: variables, coordinates: candidates, usage: &usage))
            guardEquations.append(try polynomial.remapped(to: variables, coordinates: free, usage: &usage))
        }
        let predicateIdeal = try ExactIntersectionIdeal.prepare(equations: guardEquations,
            variableCount: variables, usage: &usage)
        try RationalAlgebraStorage.retain(polynomials.count, of: ExactIntersectionPolynomial.self, usage: &usage)
        for index in polynomials.indices {
            try intersectionAlgebraStep(&usage)
            if index < source.signs.count && source.signs[index] == .zero { continue }
            polynomials[index] = try ExactIntersectionGroebnerBasis.reduced(polynomials[index],
                by: predicateIdeal.reducedBasis, usage: &usage)
        }
        let predicateReduction: OriginalPositiveGuardPolynomialReduction?
        if let axis = mobile.last {
            predicateReduction = try .prepare(polynomials: &polynomials, original: originalPredicates,
                source: source, candidateCoordinates: candidates, candidateCoordinate: candidates[axis], ideal: predicateIdeal,
                radiusIndex: radiusIndex, usage: &usage)
        } else { predicateReduction = nil }
        let quantifiedGeometryCount = geometryCount - (predicateReduction == nil ? 0 : 1)
        if predicateReduction != nil { variables -= 1 }
        let freeSupportReduction = try OriginalPositiveGuardPolynomialReduction.prepareFreeSupport(
            polynomials: &polynomials, source: source, usage: &usage)
        // Original free-coordinate conditions are partition witnesses, not extra
        // constraints. They prove target membership constant on each free cell.
        for level in partition.tower.levels {
            for polynomial in level.sources {
                try intersectionAlgebraStep(&usage)
                let mapped = try polynomial.remapped(to: variables, coordinates: free, usage: &usage)
                var duplicate = false
                for existing in polynomials {
                    if try existing.matches(mapped, usage: &usage) { duplicate = true; break }
                }
                if !duplicate {
                    try RationalAlgebraStorage.retain(1, of: ExactIntersectionPolynomial.self, usage: &usage)
                    polynomials.append(mapped)
                }
            }
        }
        // Continuity preserves zero and weakens strict signs on the closure.
        // Retain these original free-coordinate guards so exterior
        // prefixes can be proved without evaluating irrelevant candidate fibers.
        var closedGuards: [(index: Int, sign: ExactAlgebraicRealRoot.Sign)] = []
        for (ordinal, sourcePolynomial) in source.polynomials.enumerated() {
            try intersectionAlgebraStep(&usage)
            if sourcePolynomial.isZero { continue }
            let mapped = try sourcePolynomial.remapped(to: variables, coordinates: free, usage: &usage)
            var selected: Int?
            for (index, existing) in polynomials.enumerated() {
                if try existing.matches(mapped, usage: &usage) { selected = index; break }
            }
            guard let index = selected else { throw rationalAlgebraFailure("A closure lost its original closed-support witness.") }
            var duplicate = false
            for guardIndex in closedGuards {
                try intersectionAlgebraStep(&usage)
                if guardIndex.index == index { duplicate = true; break }
            }
            if !duplicate {
                try RationalAlgebraStorage.retain(1, of: (Int, ExactAlgebraicRealRoot.Sign).self, usage: &usage)
                closedGuards.append((index, source.signs[ordinal]))
            }
        }
        let neighborhoodInstructions = try rationalAlgebraCount(rationalAlgebraCount(geometryCount, 4, multiply: true), 4)
        let instructionCount = try rationalAlgebraCount(rationalAlgebraCount(source.signs.count, 2, multiply: true), rationalAlgebraCount(neighborhoodInstructions, rationalAlgebraCount(closedGuards.count, 4, multiply: true)))
        try RationalAlgebraStorage.retain(instructionCount, of: ExactIntersectionBooleanProgram.Instruction.self, usage: &usage)
        var instructions: [ExactIntersectionBooleanProgram.Instruction] = [.atom(radiusIndex, .positive), .not, .literal(true)]
        instructions.reserveCapacity(instructionCount)
        for (index, sign) in source.signs.enumerated() {
            try intersectionAlgebraStep(&usage)
            instructions.append(.atom(index, sign)); instructions.append(.and)
        }
        let boxEnd = try rationalAlgebraCount(boxIndex, rationalAlgebraCount(geometryCount, 2, multiply: true))
        for index in boxIndex..<boxEnd {
            try intersectionAlgebraStep(&usage)
            instructions.append(.atom(index, .positive)); instructions.append(.and)
        }
        instructions.append(.or)
        for guardCondition in closedGuards {
            try intersectionAlgebraStep(&usage)
            instructions.append(.atom(guardCondition.index, .zero))
            if guardCondition.sign != .zero {
                instructions.append(.atom(guardCondition.index, guardCondition.sign)); instructions.append(.or)
            }
            instructions.append(.and)
        }
        let program = try ExactIntersectionBooleanProgram(polynomialCount: polynomials.count, instructions: instructions, usage: &usage)
        let quantifierCount = try rationalAlgebraCount(quantifiedGeometryCount, 1)
        try RationalAlgebraStorage.retain(quantifierCount, of: ExactIntersectionQuantifiedCells.Quantifier.self, usage: &usage)
        var quantifiers: [ExactIntersectionQuantifiedCells.Quantifier] = [.forall]
        quantifiers.reserveCapacity(quantifierCount)
        for _ in 0..<quantifiedGeometryCount { quantifiers.append(.exists) }
        let truth = try ExactIntersectionQuantifiedCells.prepare(polynomials: polynomials, program: program,
            variableCount: variables, freeVariableCount: count, quantifiers: quantifiers,
            freeDomainEquations: closedSupport, freeDomains: partition.domains, coefficientVariableCount: coefficientCount,
            maximumCoefficientDepth: partition.maximumCoefficientDepth,
            inheritedParameterDepth: partition.cells[cellIndex].admissionDepth,
            inheritedCoefficientDepth: partition.cells[cellIndex].coefficientAdmissionDepth,
            maximumDepth: maximumDepth, usage: &usage)
        guard let freePartition = truth.freePartition else { throw rationalAlgebraFailure("An original closure lost its whole free-coordinate cover.") }
        var included: [Int] = []
        for cell in truth.freeCells where cell.value {
            try intersectionAlgebraStep(&usage)
            try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
            included.append(cell.cellIndex)
        }
        return Self(source: source, proof: .quantified(truth), freePartition: freePartition, includedCells: included,
            originalPredicates: originalPredicates, predicateIdeal: predicateIdeal, candidateCoordinateMap: candidates, predicateReduction: predicateReduction, freeSupportReduction: freeSupportReduction)
    }

    private static func isFixedOriginalCoordinate<B: ExactScalarAdmission & ~Copyable>(_ axis: Int,
        source: OriginalIntersectionCellCondition, usage: inout B) throws -> Bool {
        for index in source.polynomials.indices where source.signs[index] == .zero {
            try intersectionAlgebraStep(&usage)
            let polynomial = source.polynomials[index]
            if polynomial.isZero || polynomial.isConstant { continue }
            var linear = false, scalarLaw = true
            for term in try polynomial.orderedTerms(usage: &usage) {
                for coordinate in 0..<source.variableCount {
                    try intersectionAlgebraStep(&usage)
                    let power = try term.key.exponent(at: coordinate)
                    if coordinate == axis {
                        if power > 1 { scalarLaw = false; break }
                        if power == 1 { linear = true }
                    } else if power != 0 { scalarLaw = false; break }
                }
                if !scalarLaw { break }
            }
            if scalarLaw && linear { return true }
        }
        return false
    }
}
