import CADCore
import CADGeometry
import Synchronization

/// One evaluation retains the same original conversion ledger for every segment.
final class EdgeOffsetConversionInvocation: Sendable {
    private struct State: Sendable {
        var work = 0
        var bytes = 0
    }

    let limits: EdgeOffsetConversionLimits
    private let tolerance: ModelingTolerance
    private let state = Mutex(State())

    init(limits: EdgeOffsetConversionLimits, tolerance: ModelingTolerance) throws {
        try limits.validate(tolerance: tolerance)
        self.limits = limits
        self.tolerance = tolerance
    }

    func admission() throws -> GeometryConversionAdmission {
        try GeometryConversionAdmission(maximumSpanCount: limits.maximumSpanCount,
            maximumSubdivisionDepth: limits.maximumSubdivisionDepth,
            remainingSourceDepth: limits.remainingSourceDepth,
            consumeWork: { try self.charge(work: $0, bytes: 0) },
            consumeStorage: { try self.charge(work: 0, bytes: $0) },
            maximumAlgebraicDepth: limits.maximumAlgebraicDepth)
    }

    private func charge(work: Int, bytes: Int) throws {
        try Task.checkCancellation()
        guard work >= 0, bytes >= 0 else {
            throw failure("Original offset conversion received a negative admission request.")
        }
        try state.withLock { value in
            let nextWork = value.work.addingReportingOverflow(work)
            let nextBytes = value.bytes.addingReportingOverflow(bytes)
            guard !nextWork.overflow, !nextBytes.overflow,
                  limits.maximumWork.map({ nextWork.partialValue <= $0 }) ?? true,
                  limits.maximumStorageBytes.map({ nextBytes.partialValue <= $0 }) ?? true else {
                throw failure("Original offset conversion exhausted its cumulative work or byte allowance.")
            }
            value.work = nextWork.partialValue
            value.bytes = nextBytes.partialValue
        }
    }

    private func failure(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded,
            tolerance: tolerance, message: message)
    }
}
