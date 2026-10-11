import CADCore

/// Imports the source-owned exact-zero translation atlas under the caller ledger.
public struct OriginalDraftedRuledSurfaceSnapshotProvider: OriginalSourceSnapshotting {
    public let field: OriginalExactScalarDomain
    public let tolerance: ModelingTolerance
    public init(field: OriginalExactScalarDomain, tolerance: ModelingTolerance) {
        self.field = field; self.tolerance = tolerance
    }
    public static func supports(_ input: borrowing OriginalDraftedRuledSurface3D) -> Bool {
        OriginalDraftedZeroTranslationRationalAtlas.supports(input)
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing OriginalDraftedRuledSurface3D,
        limits: OriginalSourceIssuanceLimits, using a: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalDraftedRuledSurfaceSnapshot> {
        do {
            try a.checkpoint(); try a.consumeWork(1); try input.validate(tolerance: tolerance)
            let depth = input.remainingSourceDepth
            guard depth > 1, limits.remainingSourceDepth >= depth else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            let original = copy input
            let prepared = try ExactScalarNumericAccess.withAdmission(&a) { usage in
                try OriginalDraftedZeroTranslationRationalAtlas.prepared(original, usage: &usage)
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): General drafted wall supply lacks
            // its original ordered-field position atlas. The public source provider
            // must reject unavailable authority before complete-domain publication.
            guard let atlas = prepared.value else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            let ring = try ExactPolynomialDomain(field: field, variableCount: 2, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: atlas.cells.count, of: OriginalRetainedSurfaceCell<OriginalExactScalarDomain>.self))
            var cells: [OriginalRetainedSurfaceCell<OriginalExactScalarDomain>] = []; cells.reserveCapacity(atlas.cells.count)
            for cell in atlas.cells {
                try a.consumeWork(1)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: ExactPolynomial<OriginalExactScalarDomain>.self))
                var position: [ExactPolynomial<OriginalExactScalarDomain>] = []; position.reserveCapacity(4)
                for p in cell.homogeneous {
                    try a.retainStorage(bytes: exactScalarPayloadBytes(count: p.originalCoefficients.count, of: ExactPolynomialTerm<OriginalExactScalar>.self))
                    var terms: [ExactPolynomialTerm<OriginalExactScalar>] = []; terms.reserveCapacity(p.originalCoefficients.count)
                    let ordered = try ExactScalarNumericAccess.withAdmission(&a) { usage in
                        try p.orderedTerms(usage: &usage)
                    }.value
                    for (power, value) in ordered {
                        try a.consumeWork(1); try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Int.self))
                        terms.append(.init(powers: [power.u, power.v], coefficient: try field.rational(exactly: value, using: &a)))
                    }
                    position.append(try ring.polynomial(terms: terms, using: &a))
                }
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: OriginalSourceParameterInterval<OriginalExactScalar>.self))
                let support: [OriginalSourceParameterInterval<OriginalExactScalar>] = [
                    .init(lower: try field.rational(exactly: cell.lowerU, using: &a), upper: try field.rational(exactly: cell.upperU, using: &a)),
                    .init(lower: try field.rational(exactly: cell.lowerV, using: &a), upper: try field.rational(exactly: cell.upperV, using: &a))]
                cells.append(.init(homogeneous: position, support: support))
            }
            let generatorOffset = try field.rational(exactly: atlas.generatorOffset, using: &a)
            let generatorGain = try field.rational(exactly: atlas.generatorGain, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalDraftedRuledSurfaceSnapshot.self))
            let result = OriginalDraftedRuledSurfaceSnapshot(original: copy input, field: field,
                polynomials: ring, atlas: atlas, proofDepth: prepared.depth, cells: cells,
                generatorOffset: generatorOffset, generatorGain: generatorGain)
            try a.checkpoint(); return .init(original: result, sourceDepth: depth)
        } catch { throw .init(preserving: error) }
    }
}
