import CADCore
import CADIR
import Synchronization

/// An invocation owns one counter for reach candidates and their original proofs.
final class NaturalSheetExtensionInvocation: Sendable {
    let limits: NaturalSheetExtensionLimits
    private let tolerance: ModelingTolerance
    private let work = Mutex(0)

    init(limits: NaturalSheetExtensionLimits, tolerance: ModelingTolerance) throws {
        try limits.validate(tolerance: tolerance)
        self.limits = limits
        self.tolerance = tolerance
    }

    func consume(_ depth: Int = 0) throws {
        try Task.checkCancellation()
        guard depth >= 0, depth <= limits.maximumSubdivisionDepth else {
            throw failure("Natural sheet reach exhausted its caller subdivision depth.")
        }
        try work.withLock { count in
            let (next, overflow) = count.addingReportingOverflow(1)
            guard !overflow, limits.maximumWork.map({ next <= $0 }) ?? true else {
                throw failure("Natural sheet reach exhausted its cumulative work allowance.")
            }
            count = next
        }
    }

    private func failure(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded,
            tolerance: tolerance, message: message)
    }
}
