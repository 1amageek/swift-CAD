import CADCore

/// Descendant visits retain the original raw proof's causal depth on the same caller ledger.
struct OriginalBoundaryAdmission: Sendable {
    let parameterDepth: Int
    let coefficientDepth: Int

    func borrowing(_ original: OriginalRelationUsage, maximumDepth: Int,
        maximumCoefficientDepth: Int) throws -> OriginalRelationUsage {
        guard parameterDepth <= maximumDepth, coefficientDepth <= maximumCoefficientDepth else {
            throw rationalAlgebraFailure("Boundary query cannot reset its retained source depth.")
        }
        return .init(consumeWork: { count in
            var owner = original; try owner.consumeExactWork(count)
        }, retainStorage: { count in
            var owner = original; try owner.retainExactStorage(count)
        }, visitCell: { depth in
            let retained = try rationalAlgebraCount(parameterDepth, depth)
            guard retained <= maximumDepth else { throw rationalAlgebraFailure("Boundary refinement exceeds the original parameter depth.") }
            var owner = original; try owner.visitExactCell(depth: retained)
        }, visitCoefficientCell: { depth in
            let retained = try rationalAlgebraCount(coefficientDepth, depth)
            guard retained <= maximumCoefficientDepth else { throw rationalAlgebraFailure("Boundary refinement exceeds the original coefficient depth.") }
            var owner = original; try owner.visitCoefficientCell(depth: retained)
        })
    }
}
