import CADCore
import CADGeometry

extension OriginalSTEPPlacementSource {
    /// Validates original records and their exact normalized action under the caller allowance.
    public func validateOriginal<B: RationalAlgebraAdmitting>(tolerance: ModelingTolerance,
        maximumDepth: Int, maximumSourceDepth: Int, usage: inout B) throws {
        func element(_ value: OriginalSTEPPlacementElement?, usage: inout B) throws {
            guard let value else { return }
            try usage.visitExactCell(depth: 0)
            try usage.consumeExactWork(value.name.utf8.count + 1)
            try value.coordinates.validate()
        }
        switch self {
        case .axis2(let source):
            try element(source.location, usage: &usage)
            try element(source.axis, usage: &usage)
            try element(source.referenceDirection, usage: &usage)
        case .cartesian(let source):
            try element(source.location, usage: &usage)
            try element(source.axis1, usage: &usage)
            try element(source.axis2, usage: &usage)
            try element(source.axis3, usage: &usage)
        }
        let original = try originalNormalizedAffineSource(usage: &usage, maximumSourceDepth: maximumSourceDepth)
        _ = try OriginalAffineOperationWord(operation: .normalizedForward(original),
            tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
    }
    /// Transfers the original geometry law without its foreign record identity.
    public func originalNormalizedAffineSource<B: RationalAlgebraAdmitting>(usage: inout B, maximumSourceDepth: Int, localCoordinatesInModelUnits: Bool = false) throws -> OriginalNormalizedAffineSource {
        let count = adjustments.count
        let storage = count.multipliedReportingOverflow(by: MemoryLayout<OriginalNormalizedAffineAdjustment>.stride)
        guard !storage.overflow else { throw IndependentShapeSourceError.resourceLimitExceeded("Original normalized adjustment storage overflows.") }
        try usage.consumeExactWork(count)
        try usage.retainExactStorage(storage.partialValue / MemoryLayout<UInt32>.stride
            + (storage.partialValue % MemoryLayout<UInt32>.stride == 0 ? 0 : 1))
        var operations: [OriginalNormalizedAffineAdjustment] = []
        operations.reserveCapacity(count)
        for adjustment in adjustments {
            operations.append(.init(displacement: adjustment.displacement, conjugates: adjustment.conjugates))
        }
        let gain: ExactRationalCoefficient
        if let original = originalLengthSource { gain = try original.exactGain(maximumDepth: maximumSourceDepth, usage: &usage) }
        else { gain = try ExactRationalCoefficient.originalDouble(lengthUnit.toInternal(1), usage: &usage) }
        switch self {
        case .axis2(let value):
            return .init(family: .axis2, location: value.location.coordinates,
                axis1: value.referenceDirection?.coordinates, axis2: nil, axis3: value.axis?.coordinates,
                scale: nil, lengthGain: gain, linearGain: localCoordinatesInModelUnits ? gain : .one, adjustments: operations)
        case .cartesian(let value):
            return .init(family: .cartesian, location: value.location.coordinates,
                axis1: value.axis1?.coordinates, axis2: value.axis2?.coordinates, axis3: value.axis3?.coordinates,
                scale: value.scale, lengthGain: gain, linearGain: localCoordinatesInModelUnits ? gain : .one, adjustments: operations)
        }
    }
}
