import CADCore
import CADGeometry

extension OriginalSTEPPlacementSource {
    /// Validates original records and their exact normalized action under the caller allowance.
    public func validateOriginal(tolerance: ModelingTolerance,
        maximumDepth: Int, maximumSourceDepth: Int, using execution: inout OriginalQueryExecution) throws {
        func element(_ value: OriginalSTEPPlacementElement?, using execution: inout OriginalQueryExecution) throws {
            guard let value else { return }
            try execution.visitCell(axis: .value, depth: 0)
            try execution.consumeWork(value.name.utf8.count + 1)
            try value.coordinates.validate()
        }
        switch self {
        case .axis2(let source):
            try element(source.location, using: &execution)
            try element(source.axis, using: &execution)
            try element(source.referenceDirection, using: &execution)
        case .cartesian(let source):
            try element(source.location, using: &execution)
            try element(source.axis1, using: &execution)
            try element(source.axis2, using: &execution)
            try element(source.axis3, using: &execution)
        }
        let original = try originalNormalizedAffineSource(using: &execution, maximumSourceDepth: maximumSourceDepth)
        _ = try OriginalAffineOperationWord(operation: .normalizedForward(original),
            tolerance: tolerance, maximumDepth: maximumDepth, usage: &execution)
    }
    /// Transfers the original geometry law without its foreign record identity.
    public func originalNormalizedAffineSource(using execution: inout OriginalQueryExecution, maximumSourceDepth: Int, localCoordinatesInModelUnits: Bool = false) throws -> OriginalNormalizedAffineSource {
        let count = adjustments.count
        let storage = count.multipliedReportingOverflow(by: MemoryLayout<OriginalNormalizedAffineAdjustment>.stride)
        guard !storage.overflow else { throw IndependentShapeSourceError.resourceLimitExceeded("Original normalized adjustment storage overflows.") }
        try execution.consumeWork(count)
        try RationalAlgebraStorage.retain(storage.partialValue / MemoryLayout<UInt32>.stride
            + (storage.partialValue % MemoryLayout<UInt32>.stride == 0 ? 0 : 1), of: UInt32.self, usage: &execution)
        var operations: [OriginalNormalizedAffineAdjustment] = []
        operations.reserveCapacity(count)
        for adjustment in adjustments {
            operations.append(.init(displacement: adjustment.displacement, conjugates: adjustment.conjugates))
        }
        let gain: ExactRationalCoefficient
        if let original = originalLengthSource { gain = try original.exactGain(maximumDepth: maximumSourceDepth, using: &execution) }
        else { gain = try ExactRationalCoefficient.originalDouble(lengthUnit.toInternal(1), usage: &execution) }
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
