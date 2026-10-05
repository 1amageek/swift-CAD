import CADCore
import CADGeometry
import Synchronization

/// One shared preparation ledger; algebra depth does not become source depth.
struct BRepDrawingCuttingAdmission: RationalAlgebraAdmitting, Sendable {
    final class Owner: Sendable {
        struct State: Sendable { var work = 0; var bytes = 0 }
        let state = Mutex(State())
        let maximumWork: Int
        let maximumBytes: Int
        let maximumAlgebraicDepth: Int
        let tolerance: ModelingTolerance
        init(maximumWork: Int, maximumBytes: Int, tolerance: ModelingTolerance, maximumAlgebraicDepth: Int) {
            self.maximumWork = maximumWork; self.maximumBytes = maximumBytes; self.tolerance = tolerance
            self.maximumAlgebraicDepth = maximumAlgebraicDepth
        }
    }
    let owner: Owner
    var consumedWork: Int { owner.state.withLock { $0.work } }
    var retainedBytes: Int { owner.state.withLock { $0.bytes } }
    func consume(work: Int = 0, bytes: Int = 0) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try owner.state.withLock { state in
            guard work >= 0, bytes >= 0, work <= owner.maximumWork - state.work,
                  bytes <= owner.maximumBytes - state.bytes else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    tolerance: owner.tolerance, message: "Original cutting preparation allowance is exhausted.")
            }
            state.work += work; state.bytes += bytes
        }
    }
    func retain<T>(_ count: Int, of type: T.Type) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        guard count >= 0, !bytes.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: owner.tolerance, message: "Original cutting storage count overflowed.")
        }
        try consume(bytes: bytes.partialValue)
    }
    mutating func visitExactCell(depth: Int) throws {
        guard depth >= 0, depth <= owner.maximumAlgebraicDepth else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: owner.tolerance,
                message: "Original cutting algebra depth exceeds its caller capability.")
        }
        try consume(work: 1)
    }
    mutating func visitCoefficientCell(depth: Int) throws { try visitExactCell(depth: depth) }
    mutating func consumeExactWork(_ count: Int) throws { try consume(work: count) }
    mutating func retainExactStorage(_ count: Int) throws { try retain(count, of: UInt32.self) }
}
