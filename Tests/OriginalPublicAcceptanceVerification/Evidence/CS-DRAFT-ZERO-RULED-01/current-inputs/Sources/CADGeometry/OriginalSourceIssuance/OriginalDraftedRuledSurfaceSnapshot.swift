import CADCore

/// Retains the original wall, its exact atlas and directed child correspondence.
public struct OriginalDraftedRuledSurfaceSnapshot: OriginalRetainedSurfaceSourceReading {
    public typealias Field = OriginalExactScalarDomain
    public let original: OriginalDraftedRuledSurface3D
    public let originalField: Field
    public let originalPolynomials: ExactPolynomialDomain<Field>
    public let originalProofDepth: ExactScalarDepth
    private let atlas: OriginalDraftedZeroTranslationRationalAtlas
    private let cells: [OriginalRetainedSurfaceCell<Field>]
    private let generatorOffset: Field.Value
    private let generatorGain: Field.Value
    public var originalCellCount: Int { cells.count }
    public func originalCellLowerBound(at index: Int, axis: Int) -> Field.Value { cells[index].support[axis].lower }
    public func originalCellUpperBound(at index: Int, axis: Int) -> Field.Value { cells[index].support[axis].upper }
    public func originalCellHomogeneous(at index: Int) -> [ExactPolynomial<Field>] { cells[index].homogeneous }

    public func originalGeneratorParameter<A: ExactScalarAdmission & ~Copyable>(
        atU parameter: Field.Value, using a: inout A
    ) throws(OriginalSourceIssuanceFailure) -> Field.Value {
        do {
            try a.checkpoint()
            try a.admitDepth(value: originalProofDepth.value, coefficient: originalProofDepth.coefficient)
            let zero = try originalField.integer(0, using: &a), one = try originalField.integer(1, using: &a)
            guard try originalField.compare(parameter, zero, using: &a) != .less,
                try originalField.compare(parameter, one, using: &a) != .greater else {
                throw OriginalSourceIssuanceFailure.invalidChart
            }
            let scaled = try originalField.multiplying(generatorGain, parameter, using: &a)
            let result = try originalField.adding(generatorOffset, scaled, using: &a)
            try a.checkpoint(); return result
        } catch { throw .init(preserving: error) }
    }

    init(original: OriginalDraftedRuledSurface3D, field: Field,
        polynomials: ExactPolynomialDomain<Field>, atlas: OriginalDraftedZeroTranslationRationalAtlas,
        proofDepth: ExactScalarDepth, cells: [OriginalRetainedSurfaceCell<Field>],
        generatorOffset: Field.Value, generatorGain: Field.Value) {
        self.original = original; originalField = field; originalPolynomials = polynomials
        originalProofDepth = proofDepth; self.atlas = atlas; self.cells = cells
        self.generatorOffset = generatorOffset; self.generatorGain = generatorGain
    }
}
