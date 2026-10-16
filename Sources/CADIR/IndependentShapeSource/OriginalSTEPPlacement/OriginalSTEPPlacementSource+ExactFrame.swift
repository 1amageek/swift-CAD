import CADCore
import CADGeometry

extension OriginalSTEPPlacementSource {
    /// Admits the original normalized law in the invocation's shared exact field.
    package func originalNormalizedFrame(in context: OriginalSingularFieldContext,
        tolerance: ModelingTolerance, inheritedDepth: Int, maximumDepth: Int, maximumSourceDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> OriginalRationalNormalizedFrame {
        let count = adjustments.count
        let byteCount = count.multipliedReportingOverflow(by: MemoryLayout<(displacement: Vector3D, conjugates: Bool)>.stride)
        guard !byteCount.overflow else { throw IndependentShapeSourceError.resourceLimitExceeded("Original adjustment storage overflows.") }
        try execution.consumeWork(count)
        let words = byteCount.partialValue / MemoryLayout<UInt32>.stride
            + (byteCount.partialValue % MemoryLayout<UInt32>.stride == 0 ? 0 : 1)
        try RationalAlgebraStorage.retain(words, of: UInt32.self, usage: &execution)
        var operations: [(displacement: Vector3D, conjugates: Bool)] = []
        operations.reserveCapacity(count)
        for adjustment in adjustments {
            operations.append((adjustment.displacement, adjustment.conjugates))
        }
        let gain: ExactRationalCoefficient
        if let original = originalLengthSource { gain = try original.exactGain(maximumDepth: maximumSourceDepth, using: &execution) }
        else { gain = try ExactRationalCoefficient.originalDouble(lengthUnit.toInternal(1), usage: &execution) }
        switch self {
        case .axis2(let value):
            return try OriginalRationalNormalizedFrame(family: .axis2, location: value.location.coordinates,
                axis1: value.referenceDirection?.coordinates, axis2: nil, axis3: value.axis?.coordinates,
                scale: nil, lengthGain: gain, adjustments: operations, in: context, tolerance: tolerance,
                normalizationPolicy: .dimensionlessOriginalDirections,
                inheritedDepth: inheritedDepth, maximumDepth: maximumDepth, usage: &execution)
        case .cartesian(let value):
            return try OriginalRationalNormalizedFrame(family: .cartesian, location: value.location.coordinates,
                axis1: value.axis1?.coordinates, axis2: value.axis2?.coordinates, axis3: value.axis3?.coordinates,
                scale: value.scale, lengthGain: gain, adjustments: operations, in: context, tolerance: tolerance,
                normalizationPolicy: .dimensionlessOriginalDirections,
                inheritedDepth: inheritedDepth, maximumDepth: maximumDepth, usage: &execution)
        }
    }
}
