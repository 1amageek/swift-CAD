import CADCore

/// Reads the existing rational Hermite producer rather than interval projection caches.
public struct OriginalPlaneDerivativeCurveSnapshotProvider:OriginalSourceSnapshotting {
    public let field:OriginalExactScalarDomain
    public let tolerance:ModelingTolerance
    public init(field:OriginalExactScalarDomain,tolerance:ModelingTolerance) { self.field=field;self.tolerance=tolerance }
    public func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing OriginalPlaneDerivativeCurve3D,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalPlaneDerivativeCurveSnapshot> {
        do {
            try a.checkpoint();try a.consumeWork(1);try input.validate(tolerance:tolerance)
            guard limits.remainingSourceDepth>=input.remainingSourceDepth else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            let original=copy input
            // FIXME(INCOMPLETE_IMPLEMENTATION): General angular/algebraic derivative curve source supply still lacks its ordered-field producer. This provider delegates the existing rational original piece path; unavailable authority must fail before sealed whole-domain publication.
            let prepared=try ExactScalarNumericAccess.withAdmission(&a) { usage in
                try OriginalSplineTraversalPolynomialPiece.pieces(of:original,usage:&usage)
            }
            let ring=try ExactPolynomialDomain(field:field,variableCount:1,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:prepared.value.count,of:[ExactPolynomial<OriginalExactScalarDomain>].self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:prepared.value.count,of:OriginalSourceParameterInterval<OriginalExactScalar>.self))
            var positions:[[ExactPolynomial<OriginalExactScalarDomain>]]=[],support:[OriginalSourceParameterInterval<OriginalExactScalar>]=[]
            positions.reserveCapacity(prepared.value.count);support.reserveCapacity(prepared.value.count)
            for piece in prepared.value {
                try a.consumeWork(1)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:ExactPolynomial<OriginalExactScalarDomain>.self))
                var position:[ExactPolynomial<OriginalExactScalarDomain>]=[];position.reserveCapacity(4)
                for p in piece.homogeneous {
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:p.originalCoefficients.count,of:ExactPolynomialTerm<OriginalExactScalar>.self))
                    var terms:[ExactPolynomialTerm<OriginalExactScalar>]=[];terms.reserveCapacity(p.originalCoefficients.count)
                    for (power,value) in p.originalCoefficients {
                        try a.consumeWork(1)
                        guard power.v==0 else { throw OriginalSourceIssuanceFailure.invalidChart }
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Int.self))
                        terms.append(.init(powers:[power.u],coefficient:try field.rational(exactly:value,using:&a)))
                    }
                    position.append(try ring.polynomial(terms:terms,using:&a))
                }
                positions.append(position)
                support.append(.init(lower:try field.rational(exactly:piece.lower,using:&a),upper:try field.rational(exactly:piece.upper,using:&a)))
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalPlaneDerivativeCurveSnapshot.self))
            let result=OriginalPlaneDerivativeCurveSnapshot(original:copy input,field:field,polynomials:ring,proofDepth:prepared.depth,
                pieces:prepared.value,position:positions,support:support)
            try a.checkpoint();return .init(original:result,sourceDepth:input.remainingSourceDepth)
        } catch { throw .init(preserving:error) }
    }
}
