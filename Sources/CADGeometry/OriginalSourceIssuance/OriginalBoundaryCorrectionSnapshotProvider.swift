import CADCore

/// Exact import of retained existing correction coefficients, without reconstruction.
public struct OriginalBoundaryCorrectionSnapshotProvider:OriginalSourceSnapshotting {
    public let field:OriginalExactScalarDomain
    public let tolerance:ModelingTolerance
    public init(field:OriginalExactScalarDomain,tolerance:ModelingTolerance) { self.field=field;self.tolerance=tolerance }
    public func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing OriginalBoundaryCorrectedSurface3D,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalBoundaryCorrectionSnapshot> {
        do {
            try a.checkpoint();try a.consumeWork(1);try input.validate(tolerance:tolerance)
            let boundary=input.boundaries
            let childDepth=max(max(boundary.vMinimumBoundary.remainingSourceDepth,boundary.vMaximumBoundary.remainingSourceDepth),
                max(boundary.uMinimumBoundary.remainingSourceDepth,boundary.uMaximumBoundary.remainingSourceDepth))
            let depth=childDepth.addingReportingOverflow(1)
            guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            guard limits.remainingSourceDepth>=depth.partialValue else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            let original=copy input
            let prepared=try ExactScalarNumericAccess.withAdmission(&a) { usage in
                try OriginalBoundaryCorrectedRationalAtlas.prepared(original,usage:&usage)
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): General angular/algebraic boundary correction still lacks its ordered-field atlas. This source provider consumes the existing rational producer; unavailable authority must fail before any whole-domain family publication.
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
                    for (power,value) in p.originalCoefficients {
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
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalBoundaryCorrectionSnapshot.self))
            let result=OriginalBoundaryCorrectionSnapshot(original:copy input,field:field,polynomials:ring,atlas:atlas,proofDepth:prepared.depth,cells:cells)
            try a.checkpoint();return .init(original:result,sourceDepth:depth.partialValue)
        } catch { throw .init(preserving:error) }
    }
}

extension OriginalBoundaryCorrectionSnapshotProvider: OriginalRetainedLiftHostSnapshotting {
    public typealias Source = OriginalBoundaryCorrectionSnapshot
    public func bindHost<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Surface3D,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceBinding<Source> {
        let input=copy input
        do {
            try admission.checkpoint();try admission.consumeWork(1)
            guard case .procedural(.originalBoundaryCorrected(let host)) = input else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            return try DefaultOriginalSourceBindingIssuer(provider:self).bind(host,limits:limits,using:&admission)
        } catch { throw .init(preserving:error) }
    }
}
