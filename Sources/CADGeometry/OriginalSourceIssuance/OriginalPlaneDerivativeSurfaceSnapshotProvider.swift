import CADCore

/// Imports the original derivative-surface position atlas with its complete source.
public struct OriginalPlaneDerivativeSurfaceSnapshotProvider:OriginalSourceSnapshotting {
    public let field:OriginalExactScalarDomain
    public let tolerance:ModelingTolerance
    public init(field:OriginalExactScalarDomain,tolerance:ModelingTolerance) { self.field=field;self.tolerance=tolerance }
    public func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing OriginalPlaneDerivativeSurface3D,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalPlaneDerivativeSurfaceSnapshot> {
        do {
            try a.checkpoint();try a.consumeWork(1);try input.validate(tolerance:tolerance)
            let depth=input.remainingSourceDepth
            guard depth>1,limits.remainingSourceDepth>=depth else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            let original=copy input
            let prepared=try ExactScalarNumericAccess.withAdmission(&a) { usage in
                try OriginalPlaneDerivativeRationalAtlas.prepared(original,usage:&usage)
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): General angular/algebraic derivative surface supply still lacks its ordered-field position atlas. This provider consumes the original rational producer; unavailable authority must fail before any whole-domain family publication.
            guard let atlas=prepared.value else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            let ring=try ExactPolynomialDomain(field:field,variableCount:2,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:atlas.cells.count,of:OriginalRetainedSurfaceCell<OriginalExactScalarDomain>.self))
            var cells:[OriginalRetainedSurfaceCell<OriginalExactScalarDomain>]=[];cells.reserveCapacity(atlas.cells.count)
            for cell in atlas.cells {
                try a.consumeWork(1)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:ExactPolynomial<OriginalExactScalarDomain>.self))
                var position:[ExactPolynomial<OriginalExactScalarDomain>]=[];position.reserveCapacity(4)
                for p in cell.homogeneous {
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:p.originalCoefficients.count,of:ExactPolynomialTerm<OriginalExactScalar>.self))
                    var terms:[ExactPolynomialTerm<OriginalExactScalar>]=[];terms.reserveCapacity(p.originalCoefficients.count)
                    let ordered = try ExactScalarNumericAccess.withAdmission(&a) { usage in
                        try p.orderedTerms(usage: &usage)
                    }.value
                    for (power,value) in ordered {
                        try a.consumeWork(1);try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Int.self))
                        terms.append(.init(powers:[power.u,power.v],coefficient:try field.rational(exactly:value,using:&a)))
                    }
                    position.append(try ring.polynomial(terms:terms,using:&a))
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:OriginalSourceParameterInterval<OriginalExactScalar>.self))
                let support:[OriginalSourceParameterInterval<OriginalExactScalar>]=[
                    .init(lower:try field.rational(exactly:cell.lowerU,using:&a),upper:try field.rational(exactly:cell.upperU,using:&a)),
                    .init(lower:try field.rational(exactly:cell.lowerV,using:&a),upper:try field.rational(exactly:cell.upperV,using:&a))]
                cells.append(.init(homogeneous:position,support:support))
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalPlaneDerivativeSurfaceSnapshot.self))
            let result=OriginalPlaneDerivativeSurfaceSnapshot(original:copy input,field:field,polynomials:ring,atlas:atlas,proofDepth:prepared.depth,cells:cells)
            try a.checkpoint();return .init(original:result,sourceDepth:depth)
        } catch { throw .init(preserving:error) }
    }
}
