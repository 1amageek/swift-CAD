import CADCore

/// Imports the source-owned projected atlas without manufacturing original XYZ coefficients.
package struct OriginalDraftedProjectionSnapshotProvider: OriginalSourceSnapshotting {
    package let field:OriginalExactScalarDomain
    package func snapshot<A: ExactScalarAdmission & ~Copyable>(
        _ input: borrowing OriginalDraftedCoordinateProjection,limits:OriginalSourceIssuanceLimits,
        using a:inout A
    ) throws(OriginalSourceIssuanceFailure)->OriginalSourceSnapshot<OriginalDraftedProjectionSnapshot> {
        do {
            try a.checkpoint()
            guard limits.remainingSourceDepth>=input.sourceDepth else {
                throw OriginalSourceIssuanceFailure.sourceDepthLimit
            }
            try a.admitDepth(value:input.proofDepth.value,coefficient:input.proofDepth.coefficient)
            let ring=try ExactPolynomialDomain(field:field,variableCount:2,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:input.cells.count,of:OriginalRetainedSurfaceCell<OriginalExactScalarDomain>.self))
            var cells:[OriginalRetainedSurfaceCell<OriginalExactScalarDomain>]=[];cells.reserveCapacity(input.cells.count)
            for cell in input.cells {
                try a.consumeWork(1)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:ExactPolynomial<OriginalExactScalarDomain>.self))
                var position:[ExactPolynomial<OriginalExactScalarDomain>]=[];position.reserveCapacity(4)
                for polynomial in cell.homogeneous {
                    let ordered=try ExactScalarNumericAccess.withAdmission(&a) { usage in
                        try polynomial.orderedTerms(usage:&usage)
                    }.value
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:ordered.count,of:ExactPolynomialTerm<OriginalExactScalar>.self))
                    var terms:[ExactPolynomialTerm<OriginalExactScalar>]=[];terms.reserveCapacity(ordered.count)
                    for (power,coefficient) in ordered {
                        try a.consumeWork(1)
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Int.self))
                        terms.append(.init(powers:[power.u,power.v],coefficient:try field.rational(exactly:coefficient,using:&a)))
                    }
                    position.append(try ring.polynomial(terms:terms,using:&a))
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:OriginalSourceParameterInterval<OriginalExactScalar>.self))
                let support:[OriginalSourceParameterInterval<OriginalExactScalar>]=[
                    .init(lower:try field.rational(exactly:cell.lower,using:&a),upper:try field.rational(exactly:cell.upper,using:&a)),
                    .init(lower:try field.integer(0,using:&a),upper:try field.integer(1,using:&a))]
                cells.append(.init(homogeneous:position,support:support))
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalDraftedProjectionSnapshot.self))
            let result=OriginalDraftedProjectionSnapshot(original:copy input,originalField:field,
                originalPolynomials:ring,originalProofDepth:input.proofDepth,cells:cells)
            try a.checkpoint();return .init(original:result,sourceDepth:input.sourceDepth)
        } catch { throw .init(preserving:error) }
    }
}
