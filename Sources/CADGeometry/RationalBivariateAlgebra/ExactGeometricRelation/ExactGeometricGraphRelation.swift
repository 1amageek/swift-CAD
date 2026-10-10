#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

/// Complete geometric evidence over the original-parameter projection, retaining every auxiliary lift.
public struct ExactGeometricGraphRelation<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let original: ExactParametricGraphRelation<Base>
    public let evidenceKind: ExactGeometricEvidenceKind
    public let strata: [ExactGeometricStratumRecord]
    public let graph: ExactRealCellPullback<Base>?
    public let depth: ExactScalarDepth
    let proofs: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>]
    let parameterOrdinals: [Int]
    let graphPrefixes: [ExactRealCellID<Base>]
    public var isEmpty: Bool { original.selection.cells.isEmpty }
    public var hasPositiveDimensionalSolutions: Bool { strata.contains { $0.parameterDimension > 0 } }
    public var hasPositiveDimensionalImage: Bool { strata.contains { $0.imageDimension > 0 } }
    init(original: ExactParametricGraphRelation<Base>, evidenceKind: ExactGeometricEvidenceKind,
        strata: [ExactGeometricStratumRecord], graph: ExactRealCellPullback<Base>?, depth: ExactScalarDepth,
        proofs: [ExactPolynomial<ExactAlgebraicScalarDomain<Base>>], parameterOrdinals: [Int], graphPrefixes: [ExactRealCellID<Base>]) {
        self.original = original; self.evidenceKind = evidenceKind; self.strata = strata
        self.graph = graph; self.depth = depth; self.proofs = proofs
        self.parameterOrdinals = parameterOrdinals; self.graphPrefixes = graphPrefixes
    }
    /// Original parameter cells and all their auxiliary witnesses remain owned by L5.
    public func parameterCell(forStratum ordinal: Int) -> ExactRealCellID<Base>? {
        guard ordinal >= 0, ordinal < parameterOrdinals.count, parameterOrdinals[ordinal] >= 0 else { return nil }
        return original.selection.cells[parameterOrdinals[ordinal]]
    }
    public func graphPrefix(forStratum ordinal: Int) -> ExactRealCellID<Base>? {
        guard ordinal >= 0, ordinal < graphPrefixes.count else { return nil }
        return graphPrefixes[ordinal]
    }
}
