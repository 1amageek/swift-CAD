import CADCore

/// Exact closure of one original cell, retaining a complete refined free-space cover.
package struct OriginalIntersectionCellClosure: Sendable {
    package enum Proof: Sendable {
        case point
        case monicBranch(OriginalMonicBranchClosure)
        case affineCell(OriginalAffineCellClosure)
        case quantified(ExactIntersectionQuantifiedCells)
    }
    package let source: OriginalIntersectionCellCondition
    package let proof: Proof
    package let freePartition: OriginalRationalIntersectionCells
    package let includedCells: [Int]
    package let originalPredicates: [ExactIntersectionPolynomial]
    package let predicateIdeal: ExactIntersectionIdeal?

    private init(source: OriginalIntersectionCellCondition, proof: Proof,
        freePartition: OriginalRationalIntersectionCells, includedCells: [Int],
        originalPredicates: [ExactIntersectionPolynomial], predicateIdeal: ExactIntersectionIdeal?) {
        self.source = source; self.proof = proof
        self.freePartition = freePartition; self.includedCells = includedCells
        self.originalPredicates = originalPredicates; self.predicateIdeal = predicateIdeal
    }

    package static func prepare<B: RationalAlgebraAdmitting>(partition: OriginalRationalIntersectionCells,
        cellIndex: Int, allowAffineProofs: Bool = true, maximumDepth: Int, usage: inout B) throws -> Self {
        let source = try OriginalIntersectionCellCondition(partition: partition, cellIndex: cellIndex, usage: &usage)
        let count = source.variableCount
        guard (1...4).contains(count) else {
            throw rationalAlgebraFailure("CS/SSI closure requires at most four original parameter coordinates.")
        }
        guard maximumDepth >= 0, partition.cells[cellIndex].admissionDepth <= maximumDepth else {
            throw rationalAlgebraFailure("Original closure cannot reset its issued source-cell depth.")
        }
        if partition.cells[cellIndex].dimension == 0 {
            try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
            return Self(source: source, proof: .point, freePartition: partition, includedCells: [cellIndex],
                originalPredicates: source.polynomials, predicateIdeal: nil)
        }
        if let monic = try OriginalMonicBranchClosure.prepare(partition: partition,
            cellIndex: cellIndex, maximumDepth: maximumDepth, usage: &usage) {
            return Self(source: source, proof: .monicBranch(monic), freePartition: partition, includedCells: monic.includedCells,
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
        let variables = try rationalAlgebraCount(rationalAlgebraCount(count, 2, multiply: true), 1)
        try RationalAlgebraStorage.retain(count, of: Int.self, usage: &usage)
        let candidates = Array((count + 1)..<variables)
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
        for axis in 0..<count {
            try intersectionAlgebraStep(&usage)
            let p = try ExactIntersectionPolynomial.coordinate(variableCount: variables, at: axis, usage: &usage)
            let q = try ExactIntersectionPolynomial.coordinate(variableCount: variables, at: count + 1 + axis, usage: &usage)
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
        let instructionCount = try rationalAlgebraCount(rationalAlgebraCount(source.signs.count, 2, multiply: true), rationalAlgebraCount(rationalAlgebraCount(count, 4, multiply: true) + 4, rationalAlgebraCount(closedGuards.count, 4, multiply: true)))
        try RationalAlgebraStorage.retain(instructionCount, of: ExactIntersectionBooleanProgram.Instruction.self, usage: &usage)
        var instructions: [ExactIntersectionBooleanProgram.Instruction] = [.atom(radiusIndex, .positive), .not, .literal(true)]
        instructions.reserveCapacity(instructionCount)
        for (index, sign) in source.signs.enumerated() {
            try intersectionAlgebraStep(&usage)
            instructions.append(.atom(index, sign)); instructions.append(.and)
        }
        for index in boxIndex..<(boxIndex + count * 2) {
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
        try RationalAlgebraStorage.retain(count + 1, of: ExactIntersectionQuantifiedCells.Quantifier.self, usage: &usage)
        var quantifiers: [ExactIntersectionQuantifiedCells.Quantifier] = [.forall]
        quantifiers.reserveCapacity(count + 1)
        for _ in 0..<count { quantifiers.append(.exists) }
        let truth = try ExactIntersectionQuantifiedCells.prepare(polynomials: polynomials, program: program,
            variableCount: variables, freeVariableCount: count, quantifiers: quantifiers,
            freeDomainEquations: closedSupport, maximumDepth: maximumDepth, usage: &usage)
        guard let freePartition = truth.freePartition else { throw rationalAlgebraFailure("An original closure lost its whole free-coordinate cover.") }
        var included: [Int] = []
        for cell in truth.freeCells where cell.value {
            try intersectionAlgebraStep(&usage)
            try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
            included.append(cell.cellIndex)
        }
        return Self(source: source, proof: .quantified(truth), freePartition: freePartition, includedCells: included,
            originalPredicates: originalPredicates, predicateIdeal: predicateIdeal)
    }
}
