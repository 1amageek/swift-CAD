import CADCore

/// Retains the original wrapper and its exact gain provenance, not gain estimates.
public struct OriginalParameterImageSnapshot<Original: Sendable, Child: Sendable>: OriginalParameterImageSourceReading {
    public let original: Original
    public let originalChild: OriginalSourceBinding<Child>
    public let parameterCount: Int
    public let hasSpatialAction: Bool
    private let gains: [OriginalParameterGain]
    private let offsets: [Double]
    private let swapAxes: Bool
    private let transform: AffineTransform3D?
    init(original: Original, child: OriginalSourceBinding<Child>, gains: [OriginalParameterGain],
        offsets: [Double], swapAxes: Bool, transform: AffineTransform3D?) {
        self.original = original; originalChild = child; self.gains = gains; self.offsets = offsets
        parameterCount = gains.count; self.swapAxes = swapAxes; self.transform = transform
        hasSpatialAction = transform != nil
    }
    public func childAxis(forOriginalAxis axis: Int) -> Int { swapAxes ? 1 - axis : axis }
    public func originalGain<F: ExactScalarArithmetic & ExactScalarOrdering, A: ExactScalarAdmission & ~Copyable>(
        in axis: Int, field: borrowing F, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> F.Value {
        do {
            let value = try ExactScalarNumericAccess.withAdmission(&admission) { usage in
                try gains[axis].exactCoefficient(usage: &usage)
            }.value
            return try OriginalSourceRationalImport.value(value, field: field, using: &admission)
        } catch { throw .init(preserving: error) }
    }
    public func originalOffset<F: ExactScalarArithmetic & ExactScalarOrdering, A: ExactScalarAdmission & ~Copyable>(
        in axis: Int, field: borrowing F, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> F.Value {
        do { return try field.binary64(exactly: offsets[axis], using: &admission) }
        catch { throw .init(preserving: error) }
    }
    public func originalSpatialCoefficient<F: ExactScalarArithmetic & ExactScalarOrdering, A: ExactScalarAdmission & ~Copyable>(
        row: Int, column: Int, field: borrowing F, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> F.Value {
        do {
            guard let transform else { return try field.integer(row == column ? 1 : 0, using: &admission) }
            let vector = column == 0 ? transform.basisX : column == 1 ? transform.basisY :
                column == 2 ? transform.basisZ : transform.translation
            return try field.binary64(exactly: row == 0 ? vector.x : row == 1 ? vector.y : vector.z, using: &admission)
        } catch { throw .init(preserving: error) }
    }
}
