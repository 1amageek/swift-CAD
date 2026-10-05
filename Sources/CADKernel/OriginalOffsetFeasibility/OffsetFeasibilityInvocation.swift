import CADCore
import CADGeometry
import Synchronization

/// One result-scope owner; optional ceilings add no hidden legacy allowance.
final class OffsetFeasibilityInvocation: Sendable {
    private struct State: Sendable {
        var work = 0
        var storageBytes = 0
    }

    private let state = Mutex(State())
    private let limits: OffsetFeasibilityLimits
    private let tolerance: ModelingTolerance
    private let borrowedAdmission: GeometryConversionAdmission?

    init(limits: OffsetFeasibilityLimits, tolerance: ModelingTolerance,
        borrowedAdmission: GeometryConversionAdmission? = nil) {
        self.limits = limits
        self.tolerance = tolerance
        self.borrowedAdmission = borrowedAdmission
    }

    var usesSelectedAdmission: Bool {
        borrowedAdmission != nil || limits.maximumCumulativeWork != nil
            || limits.maximumCumulativeStorageBytes != nil
    }

    var maximumSpanCount: Int {
        borrowedAdmission?.maximumSpanCount ?? limits.surfaceIntersectionOptions.maximumSubdivisionCells
    }

    var storageAdmission: (@Sendable (Int) throws -> Void)? {
        guard borrowedAdmission != nil || limits.maximumCumulativeStorageBytes != nil else { return nil }
        return { bytes in try self.retain(bytes) }
    }

    func consume(depth: Int) throws {
        try Task.checkCancellation()
        guard depth >= 0, depth <= limits.surfaceIntersectionOptions.maximumSubdivisionDepth else {
            throw failure("Offset feasibility exceeded its selected spatial depth.")
        }
        try borrowedAdmission?.visit(depth: depth)
        try state.withLock { counters in
            let next = counters.work.addingReportingOverflow(1)
            guard !next.overflow,
                limits.maximumCumulativeWork.map({ next.partialValue <= $0 }) ?? true else {
                throw failure("Offset feasibility exhausted its cumulative work allowance.")
            }
            counters.work = next.partialValue
        }
    }

    func retain(_ bytes: Int) throws {
        try Task.checkCancellation()
        guard bytes >= 0 else { throw failure("Offset feasibility byte count must be nonnegative.") }
        try borrowedAdmission?.chargeStorage(bytes: bytes)
        try state.withLock { counters in
            let next = counters.storageBytes.addingReportingOverflow(bytes)
            guard bytes >= 0, !next.overflow,
                limits.maximumCumulativeStorageBytes.map({ next.partialValue <= $0 }) ?? true else {
                throw failure("Offset feasibility exhausted its cumulative storage-byte allowance.")
            }
            counters.storageBytes = next.partialValue
        }
    }

    func reserve<T>(_ count: Int, of type: T.Type) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        guard count >= 0, !bytes.overflow else {
            throw failure("Offset feasibility typed capacity overflowed.")
        }
        try retain(bytes.partialValue)
    }

    private func failure(_ message: String) -> KernelError {
        KernelError(phase: .topology, code: .resourceLimitExceeded,
            tolerance: tolerance, message: message)
    }
}
