import CADCore
import CADGeometry
import Synchronization

/// One source-law allowance shared by every closed-frame correction attempt.
package final class CurvedSweepSourceBudget: Sendable, RationalAlgebraAdmitting {
    private struct State {
        var remainingWork: Int
        var remainingScalars: Int
    }
    private let state: Mutex<State>
    private let tolerance: ModelingTolerance
    package let maximumDepth = 20
    package let maximumSpanCount: Int

    package init(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        self.tolerance = tolerance
        let limits = GeometryConversionRequirements(maximumPositionError: tolerance.distance,
            maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance)
        maximumSpanCount = limits.maximumControlPointCount
        state = Mutex(State(remainingWork: limits.maximumWorkUnits,
            remainingScalars: limits.maximumScalarCount))
    }

    package func conversionAdmission() throws -> GeometryConversionAdmission {
        try GeometryConversionAdmission(maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumDepth, remainingSourceDepth: maximumDepth,
            consumeWork: { try self.consumeExactWork($0) },
            consumeStorage: { try self.retainBytes($0) })
    }

    package func consume(depth: Int) throws {
        try consume(count: 1, depth: depth)
    }

    private func consume(count: Int, depth: Int) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try state.withLock { value in
            guard depth >= 0, depth <= maximumDepth, count >= 0,
                  count <= value.remainingWork else { throw exhausted() }
            value.remainingWork -= count
        }
    }

    package func consumeExactWork(_ count: Int) throws { try consume(count: count, depth: 0) }
    package func retainExactStorage(_ count: Int) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard count >= 0, !bytes.overflow else { throw exhausted() }
        try retainBytes(bytes.partialValue)
    }
    package func visitExactCell(depth: Int) throws {
        guard depth >= 0, depth <= 32 else { throw exhausted() }
        try consumeExactWork(1)
    }

    package func retainScalars(_ count: Int) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try state.withLock { value in
            guard count >= 0, count <= value.remainingScalars else { throw exhausted() }
            value.remainingScalars -= count
        }
    }

    package func retainBytes(_ count: Int) throws {
        guard count >= 0 else { throw exhausted() }
        let stride = MemoryLayout<Double>.stride
        try retainScalars(count / stride + (count % stride == 0 ? 0 : 1))
    }

    private func exhausted() -> KernelError {
        KernelError(phase: .evaluation, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "The curved sweep exhausted its cumulative original-law work, scalar or depth allowance.")
    }
}
