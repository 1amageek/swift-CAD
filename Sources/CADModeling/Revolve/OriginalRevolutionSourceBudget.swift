import CADCore
import CADGeometry

/// One invocation-local exact allowance borrowed by the complete original source path.
package struct OriginalRevolutionSourceBudget: Sendable, RationalAlgebraAdmitting {
    package let maximumCells: Int
    package let maximumDepth: Int
    private var remainingWork: Int
    private var remainingStorage: Int
    private var remainingCells: Int
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        let retained = GeometryConversionRequirements(maximumPositionError: tolerance.distance,
            maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.relative)
        maximumCells = min(65_536, retained.maximumCertificationBoxes)
        maximumDepth = 32
        remainingWork = retained.maximumWorkUnits
        remainingStorage = retained.maximumScalarCount
        remainingCells = maximumCells
        self.tolerance = tolerance
    }

    package mutating func consumeExactWork(_ count: Int) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard count >= 0, count <= remainingWork else { throw exhausted() }
        remainingWork -= count
    }

    package mutating func retainExactStorage(_ count: Int) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard count >= 0, !bytes.overflow else { throw exhausted() }
        let stride = MemoryLayout<Double>.stride
        let slots = bytes.partialValue / stride + (bytes.partialValue % stride == 0 ? 0 : 1)
        guard slots <= remainingStorage else { throw exhausted() }
        remainingStorage -= slots
    }

    package mutating func visitExactCell(depth: Int) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard depth >= 0, depth <= maximumDepth, remainingCells > 0 else { throw exhausted() }
        remainingCells -= 1
    }

    private func exhausted() -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "Original revolution exhausted its cumulative source work, storage, cells or subdivision allowance.")
    }
}
