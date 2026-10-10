import CADCore

/// Imports the existing original Coons position atlas without reconstructing its formula.
public struct OriginalCoonsAtlasSnapshotProvider:OriginalSourceSnapshotting {
    public let field:OriginalExactScalarDomain
    public let tolerance:ModelingTolerance
    public init(field:OriginalExactScalarDomain,tolerance:ModelingTolerance) { self.field=field;self.tolerance=tolerance }
    public func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing OriginalCoonsSurface3D,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalCoonsAtlasSnapshot> {
        do {
            try a.checkpoint();try a.consumeWork(1);try input.validate(tolerance:tolerance)
            let boundary=copy input
            let childDepth=max(max(boundary.vMinimumBoundary.remainingSourceDepth,boundary.vMaximumBoundary.remainingSourceDepth),
                max(boundary.uMinimumBoundary.remainingSourceDepth,boundary.uMaximumBoundary.remainingSourceDepth))
            let depth=childDepth.addingReportingOverflow(1)
            guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            guard limits.remainingSourceDepth>=depth.partialValue else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            let original=copy input
            let prepared=try ExactScalarNumericAccess.withAdmission(&a) { usage in
                try OriginalCoonsHomogeneousAtlas.prepared(original,usage:&usage)
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Angular/algebraic or discontinuous Coons boundaries
            // lack a complete retained rational atlas. This actual Coons host/lift provider
            // must not publish whole-domain success until their original correspondence is proved.
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
                    let ordered=try ExactScalarNumericAccess.withAdmission(&a) { usage in
                        try p.orderedTerms(usage:&usage)
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
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalCoonsAtlasSnapshot.self))
            let result=OriginalCoonsAtlasSnapshot(original:copy input,field:field,polynomials:ring,atlas:atlas,proofDepth:prepared.depth,cells:cells)
            try a.checkpoint();return .init(original:result,sourceDepth:depth.partialValue)
        } catch { throw .init(preserving:error) }
    }
}

extension OriginalCoonsAtlasSnapshotProvider: OriginalRetainedLiftHostSnapshotting {
    public typealias Source = OriginalCoonsAtlasSnapshot
    public func bindHost<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Surface3D,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceBinding<Source> {
        let input=copy input
        do {
            try admission.checkpoint();try admission.consumeWork(1)
            guard case .procedural(.originalCoons(let host)) = input else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            return try DefaultOriginalSourceBindingIssuer(provider:self).bind(host,limits:limits,using:&admission)
        } catch { throw .init(preserving:error) }
    }
}
