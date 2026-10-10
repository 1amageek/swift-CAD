import CADCore

/// Transfers existing normalized guide laws without rebuilding station or correction formulas.
public struct OriginalRetainedGuideCurveSnapshotProvider:OriginalSourceSnapshotting {
    public let field:OriginalExactScalarDomain
    public let tolerance:ModelingTolerance
    public init(field:OriginalExactScalarDomain,tolerance:ModelingTolerance) { self.field=field;self.tolerance=tolerance }
    public func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing Curve3D,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalRetainedGuideCurveSnapshot> {
        do {
            try a.checkpoint();try a.consumeWork(1)
            let retainedDepth:Int
            switch copy input {
            case .originalGuideTraversalChain(let chain):
                try chain.validate(tolerance:tolerance);retainedDepth=chain.remainingSourceDepth
            case .originalGuideEndpointConnector(let connector):
                try connector.validate(tolerance:tolerance);retainedDepth=connector.remainingSourceDepth
            default:throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            guard limits.remainingSourceDepth>=retainedDepth else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            let original=copy input
            // FIXME(INCOMPLETE_IMPLEMENTATION): Nonrational/algebraic guide laws still need
            // their original ordered-field producer. This source port consumes the retained
            // rational producer and must not publish a complete family for unavailable laws.
            let prepared=try ExactScalarNumericAccess.withAdmission(&a) { usage in
                try OriginalSplineTraversalPolynomialPiece.pieces(of:original,remainingSourceDepth:retainedDepth,tolerance:tolerance,usage:&usage)
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
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalRetainedGuideCurveSnapshot.self))
            let result=OriginalRetainedGuideCurveSnapshot(original:copy input,field:field,polynomials:ring,proofDepth:prepared.depth,
                pieces:prepared.value,position:positions,support:support)
            try a.checkpoint();return .init(original:result,sourceDepth:retainedDepth)
        } catch { throw .init(preserving:error) }
    }
}
