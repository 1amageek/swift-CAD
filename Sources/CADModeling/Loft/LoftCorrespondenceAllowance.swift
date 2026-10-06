import CADCore
import CADGeometry
import Synchronization

/// Immutable invocation owner shared by correspondence and final image proofs.
package final class LoftCorrespondenceAllowance: Sendable {
    private let remaining: Mutex<Int>
    package let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
        let bytes = MemoryLayout<Mutex<Int>>.stride + MemoryLayout<ModelingTolerance>.stride
        let words = bytes / 4 + (bytes % 4 == 0 ? 0 : 1)
        remaining = Mutex(262_144 - words)
    }

    package func charge(_ count: Int) throws {
        try Task.checkCancellation()
        try remaining.withLock { available in
            guard count >= 0, count <= available else { throw exhausted() }
            available -= count
        }
    }

    package func retainBytes(_ bytes: Int) throws {
        guard bytes >= 0 else { throw exhausted() }
        try charge(bytes / 4 + (bytes % 4 == 0 ? 0 : 1))
    }

    package func chargeProduct(_ count: Int, _ stride: Int) throws {
        let value = count.multipliedReportingOverflow(by: stride)
        guard count >= 0, stride >= 0, !value.overflow else { throw exhausted() }
        try charge(value.partialValue)
    }

    package func retainElements<T>(_ count: Int, of type: T.Type) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        guard count >= 0, !bytes.overflow else { throw exhausted() }
        try retainBytes(bytes.partialValue)
    }
    package func conversionAdmission() throws -> GeometryConversionAdmission {
        let limits = GeometryConversionRequirements(maximumPositionError: tolerance.distance * 0.25,
            maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance)
        try retainBytes(MemoryLayout<GeometryConversionAdmission>.stride)
        return try GeometryConversionAdmission(maximumSpanCount: limits.maximumControlPointCount,
            maximumSubdivisionDepth: 20, remainingSourceDepth: 20,
            consumeWork: { try self.charge($0) }, consumeStorage: { try self.retainBytes($0) })
    }

    private func exhausted() -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "Loft correspondence exhausted its cumulative work and UInt32-word retention allowance.")
    }
}
