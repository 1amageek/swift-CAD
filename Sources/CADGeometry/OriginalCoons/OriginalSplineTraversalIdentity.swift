import CADCore

/// Compares original directed rational spline laws over an exact common parameter partition.
struct OriginalSplineTraversalIdentity {
    func proves<B: RationalAlgebraAdmitting>(_ first: OriginalCurveRootSpan3D,
        _ second: OriginalCurveRootSpan3D, usage: inout B) throws -> Bool {
        if try first.hasSameOriginalTraversal(as: second,
            consumeWork: { try usage.consumeExactWork($0) }) { return true }
        guard first.certificationTolerance == second.certificationTolerance else {
            throw GeometryConversionError.invalidInput("Original seam traversals use different tolerance bindings.")
        }
        let a = try OriginalSplineTraversalPolynomialPiece.pieces(first, usage: &usage),
            b = try OriginalSplineTraversalPolynomialPiece.pieces(second, usage: &usage)
        try usage.retainExactStorage(2)
        var cuts: [ExactRationalCoefficient] = [.zero, .one]
        for source in [a, b] {
            for piece in source {
                for cut in [piece.lower, piece.upper] {
                    var insertion = 0
                    while insertion < cuts.count {
                        let difference = try cut.subtracting(cuts[insertion], usage: &usage)
                        if !difference.isPositive { break }
                        insertion += 1
                    }
                    if insertion == cuts.count || cuts[insertion] != cut {
                        try usage.retainExactStorage(1); try usage.consumeExactWork(cuts.count - insertion + 1)
                        cuts.insert(cut, at: insertion)
                    }
                }
            }
        }
        let two = try ExactRationalCoefficient.one.adding(.one, usage: &usage)
        for index in 0..<(cuts.count - 1) {
            try CurrentTaskCancellationChecker().checkCancellation(); try usage.visitExactCell(depth: 0)
            let center = try cuts[index].adding(cuts[index + 1], usage: &usage).divided(by: two, usage: &usage)
            let firstPiece = try owner(in: a, at: center, usage: &usage)
            let secondPiece = try owner(in: b, at: center, usage: &usage)
            for coordinate in 0..<3 {
                let residual = try firstPiece.homogeneous[coordinate]
                    .multiplied(by: secondPiece.homogeneous[3], usage: &usage)
                    .subtracting(secondPiece.homogeneous[coordinate]
                        .multiplied(by: firstPiece.homogeneous[3], usage: &usage), usage: &usage)
                if !residual.isZero { return false }
            }
        }
        return true
    }

    private func owner<B: RationalAlgebraAdmitting>(in pieces: [OriginalSplineTraversalPolynomialPiece], at parameter: ExactRationalCoefficient,
        usage: inout B) throws -> OriginalSplineTraversalPolynomialPiece {
        for piece in pieces {
            let lower = try parameter.subtracting(piece.lower, usage: &usage)
            let upper = try piece.upper.subtracting(parameter, usage: &usage)
            if lower.isPositive && upper.isPositive { return piece }
        }
        throw GeometryConversionError.invalidInput("Original seam partition omitted a positive parameter interval.")
    }

}
