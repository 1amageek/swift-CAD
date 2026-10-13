import CADCore

/// Source-owned rational coordinate projection; the original wall remains authoritative.
package struct OriginalDraftedCoordinateProjection: Sendable {
    package struct Cell: Sendable {
        package let lower: ExactRationalCoefficient
        package let upper: ExactRationalCoefficient
        package let homogeneous: [ExactBivariatePolynomial]
    }
    package let original: OriginalDraftedRuledSurface3D
    package let cells: [Cell]
    package let proofDepth: ExactScalarDepth
    // Direct Native traversal, drafted curve, then ruled surface: three source edges.
    package var sourceDepth: Int { 3 }

    package static func supports(_ wall: borrowing OriginalDraftedRuledSurface3D) -> Bool {
        let start=wall.start
        guard start.normal.x==0,start.normal.y==0,start.normal.z != 0,
            start.axis.x==0,start.axis.y==0,start.axis.z != 0,start.pull==start.axis,
            case .bSpline(let native)=start.generator.source,
            case .authored=start.generator.start,case .authored=start.generator.end,
            let first=native.controlPoints.first else { return false }
        return native.controlPoints.allSatisfy { $0.y==first.y && $0.z==first.z }
    }

    package static func prepare<A: ExactScalarAdmission & ~Copyable>(
        _ wall: OriginalDraftedRuledSurface3D,limits: OriginalSourceIssuanceLimits,
        using a: inout A
    ) throws(OriginalSourceIssuanceFailure) -> Self {
        do {
            try a.checkpoint()
            guard supports(wall) else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            guard wall.remainingSourceDepth>1,limits.remainingSourceDepth>=3 else {
                throw OriginalSourceIssuanceFailure.sourceDepthLimit
            }
            let prepared=try ExactScalarNumericAccess.withAdmission(&a) { usage in
                try wall.validate(tolerance:wall.certificationTolerance)
                // This is source guard admission, not equality from an enclosure.
                func storage(_ bytes:Int) throws { try RationalAlgebraStorage.retainBytes(bytes,usage:&usage) }
                _ = try withoutActuallyEscaping(storage) { storage in
                    try wall.start.rulingJet(over:.init(lower:0,upper:1),throughOrder:0,
                    tolerance:wall.certificationTolerance,maximumSpanCount:wall.maximumSpanCount,
                    maximumSubdivisionDepth:wall.maximumSubdivisionDepth,
                    remainingSourceDepth:min(wall.remainingSourceDepth,limits.remainingSourceDepth)-1,
                    consumeWork:{ try usage.consumeExactWork(1) },
                    consumeStorage:storage)
                }
                let pieces=try OriginalSplineTraversalPolynomialPiece.pieces(wall.start.generator,usage:&usage)
                guard pieces.count<=wall.maximumSpanCount else { throw OriginalSourceIssuanceFailure.chartLimit }
                typealias Q=ExactRationalCoefficient
                typealias P=ExactBivariatePolynomial
                let start=try Q.originalDouble(wall.start.height,usage:&usage)
                let delta=try Q.originalDouble(wall.endHeight,usage:&usage).subtracting(start,usage:&usage)
                let sign=try Q.originalDouble(wall.start.axis.z>0 ? 1:-1,usage:&usage)
                let height=try P.coordinate(alongU:false,usage:&usage).scaled(by:delta,usage:&usage)
                    .adding(.constant(start,usage:&usage),usage:&usage).scaled(by:sign,usage:&usage)
                try RationalAlgebraStorage.retain(pieces.count,of:Cell.self,usage:&usage)
                var cells:[Cell]=[];cells.reserveCapacity(pieces.count)
                for piece in pieces {
                    try usage.consumeExactWork(1)
                    try RationalAlgebraStorage.retain(4,of:P.self,usage:&usage)
                    let z=try piece.homogeneous[2].adding(piece.homogeneous[3].multiplied(by:height,usage:&usage),usage:&usage)
                    cells.append(.init(lower:piece.lower,upper:piece.upper,
                        homogeneous:[piece.homogeneous[0],z,.zero,piece.homogeneous[3]]))
                }
                return cells
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Self.self))
            let result=Self(original:wall,cells:prepared.value,proofDepth:prepared.depth)
            try a.checkpoint();return result
        } catch { throw .init(preserving:error) }
    }
    private init(original: OriginalDraftedRuledSurface3D,cells:[Cell],proofDepth:ExactScalarDepth) {
        self.original=original;self.cells=cells;self.proofDepth=proofDepth
    }
}
