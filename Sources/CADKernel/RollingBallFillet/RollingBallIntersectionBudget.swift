import CADCore
import CADGeometry
import Synchronization

/// Shares the existing crossing allowance across one final patch network.
final class RollingBallIntersectionBudget: Sendable {
    private struct State {
        var work = 65_536
        var scalars: Int
    }
    private let state: Mutex<State>
    private let tolerance: ModelingTolerance
    let maximumDepth = 20
    let maximumSourceDepth = 20
    let maximumAlgebraicDepth = 32

    init(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        self.tolerance = tolerance
        let limits = GeometryConversionRequirements(maximumPositionError: tolerance.distance,
            maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance)
        state = Mutex(State(scalars: limits.maximumScalarCount))
    }

    func consume(depth: Int = 0) throws {
        try consume(count: 1, depth: depth)
    }

    func hasOriginalTolerance(_ tolerance: ModelingTolerance) -> Bool { self.tolerance == tolerance }

    func consume(count: Int, depth: Int = 0) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try state.withLock { value in
            guard depth >= 0, depth <= maximumDepth, count >= 0,
                  count <= value.work else { throw exhausted() }
            value.work -= count
        }
    }

    func retainScalars(_ count: Int) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try state.withLock { value in
            guard count >= 0, count <= value.scalars else { throw exhausted() }
            value.scalars -= count
        }
    }

    func retainBytes(_ count: Int) throws {
        guard count >= 0 else { throw exhausted() }
        let stride = MemoryLayout<Double>.stride
        let scalars = count / stride + (count % stride == 0 ? 0 : 1)
        try retainScalars(scalars)
    }

    private func exhausted() -> KernelError {
        KernelError(phase: .classification, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "Rolling-ball crossing proof exhausted its cumulative original work, storage or depth allowance.")
    }
}
